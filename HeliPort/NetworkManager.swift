//
//  NetworkManager.swift
//  HeliPort
//
//  Created by 梁怀宇 on 2020/3/23.
//  Copyright © 2020 OpenIntelWireless. All rights reserved.
//

/*
 * This program and the accompanying materials are licensed and made available
 * under the terms and conditions of the The 3-Clause BSD License
 * which accompanies this distribution. The full text of the license may be found at
 * https://opensource.org/licenses/BSD-3-Clause
 */

import Foundation
import AppKit
import SystemConfiguration

final class NetworkManager {
    static let joinSession = JoinSession()
    private static let connectionRequest = WorkGate()
    private static let autoJoinRequest = WorkGate()
    private static let autoJoinTimer = MainRunLoopTimer()
    private static var authWindow: WiFiConfigWindow?
    private static var scanCallbacks = [(Set<NetworkInfo>) -> Void]() // Main-thread only.
    static let supportedSecurityMode = [
        ITL80211_SECURITY_NONE, ITL80211_SECURITY_WPA2_PERSONAL
    ]

    static func connect(networkInfo: NetworkInfo, saveNetwork: Bool = false, interactive: Bool = true,
                        _ callback: ((_ result: Bool) -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { connect(networkInfo: networkInfo, saveNetwork: saveNetwork, interactive: interactive, callback) }
            return
        }
        guard let token = connectionRequest.begin() else {
            Log.debug("Ignored repeated join while a connection or password prompt is active")
            authWindow?.makeKeyAndOrderFront(nil)
            callback?(false)
            return
        }

        let finish: (Bool, String?) -> Void = { result, error in
            DispatchQueue.main.async {
                guard connectionRequest.finish(token) else { return }
                authWindow = nil
                if interactive, let error { Alert(text: error).show() }
                callback?(result)
            }
        }

        guard networkInfo.canJoin != false else {
            finish(false, "This network is not joinable by the current MT7902 driver (open or WPA2-PSK/CCMP, optional PMF, supported channels only; open Wi-Fi requires driver 0.2.16 or newer).")
            return
        }

        guard supportedSecurityMode.contains(networkInfo.auth.security) else {
            finish(false, NSLocalizedString("Network security not supported: ") + networkInfo.auth.security.description)
            return
        }

        // The menu refreshes and reuses NetworkInfo objects. A join owns a separate
        // snapshot, so keychain work never mutates a row while AppKit renders it.
        let request = NetworkInfo(ssid: networkInfo.ssid, rssi: networkInfo.rssi)
        request.auth.security = networkInfo.auth.security
        request.auth.password = networkInfo.auth.password
        var submitted = false // Accessed only on main, including dialog close.
        let getAuthInfoCallback: (NetworkAuth, Bool) -> Void = { auth, savePassword in
            let submit = {
                guard connectionRequest.isCurrent(token), !submitted else { return }
                submitted = true
                request.auth = auth
                joinSession.remember(request, auth: auth)
                let password = auth.password
                StatusBarIcon.shared().connecting()
                DispatchQueue.global(qos: .background).async {
                    let result = connect_network(request.ssid, password)
                    if result {
                        joinSession.succeeded(request.ssid)
                        if savePassword { CredentialsManager.instance.save(request) }
                    }
                    var detail: String?
                    if !result {
                        var error = [CChar](repeating: 0, count: 256)
                        mt7902_copy_error(&error, error.count)
                        let text = String(cString: error)
                        detail = text.isEmpty ? "The MT7902 driver could not join this network." : text
                    }
                    finish(result, detail)
                }
            }
            if Thread.isMainThread { submit() }
            else { DispatchQueue.main.async(execute: submit) }
        }

        // Getting keychain access blocks UI Thread and makes everything freeze unless made async
        DispatchQueue.global().async {
            // An open observation must never retrieve a password saved for an
            // older protected hotspot with the same SSID.
            if request.auth.security == ITL80211_SECURITY_NONE {
                request.auth.password = ""
                getAuthInfoCallback(request.auth, saveNetwork)
                return
            }
            if !request.auth.password.isEmpty {
                getAuthInfoCallback(request.auth, saveNetwork)
                return
            }
            if let cached = joinSession.credentials(for: request) {
                getAuthInfoCallback(cached, saveNetwork)
                return
            }
            if let saved = CredentialsManager.instance.get(request, interactive: interactive),
               saved.security == request.auth.security {
                getAuthInfoCallback(saved, false)
                return
            }
            // Background auto-join may fail silently; it never opens either a
            // Keychain authorization dialog or the app's Wi-Fi password window.
            guard interactive else { finish(false, nil); return }

            DispatchQueue.main.async {
                guard connectionRequest.isCurrent(token) else { return }
                let window = WiFiConfigWindow(windowState: .connectWiFi,
                                              networkInfo: request,
                                              getAuthInfoCallback: getAuthInfoCallback)
                authWindow = window
                window.onClose = {
                    authWindow = nil
                    if !submitted { finish(false, nil) }
                }
                window.show()
                if !window.isVisible { window.close() }
            }
        }
    }

    static func scanNetwork(sortBy areInIncreasingOrder: @escaping (NetworkInfo, NetworkInfo) -> Bool
                                = { $0.ssid < $1.ssid },
                            callback: @escaping (_ sortedNetworkInfoList: [NetworkInfo]) -> Void) {
        scanNetwork { result in
            callback(result.sorted(by: areInIncreasingOrder))
        }
    }

    static func scanNetwork(sortBy areInIncreasingOrder: @escaping (NetworkInfo, NetworkInfo) -> Bool
                                = { $0.ssid < $1.ssid },
                            callback: @escaping (_ knownNetworks: [NetworkInfo],
                                                 _ otherNetworks: [NetworkInfo]) -> Void) {
        DispatchQueue.global(qos: .background).async {
            let savedSSIDs = CredentialsManager.instance.getSavedNetworkSSIDs()
            scanNetwork { result in
                let known = result.filter { savedSSIDs.contains($0.ssid) }
                let other = result.subtracting(known)

                DispatchQueue.main.async {
                    callback(known.sorted(by: areInIncreasingOrder),
                             other.sorted(by: areInIncreasingOrder))
                }
            }
        }
    }

    private static func scanNetwork(callback: @escaping (_ networkInfoList: Set<NetworkInfo>) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { scanNetwork(callback: callback) }
            return
        }
        scanCallbacks.append(callback)
        guard scanCallbacks.count == 1 else { return }
        DispatchQueue.global(qos: .background).async {
            var list = network_info_list_t()
            get_network_list(&list)

            var result = Set<NetworkInfo>()
            let networks = Mirror(reflecting: list.networks).children.map({ $0.value }).prefix(Int(list.count))

            for element in networks {
                guard let network = element as? ioctl_network_info else {
                    continue
                }
                let ssid = String(ssid: network.ssid)
                guard !ssid.isEmpty else {
                    continue
                }

                let networkInfo = NetworkInfo(
                    ssid: ssid,
                    rssi: Int(network.rssi)
                )
                networkInfo.auth.security = getSecurityType(network)
                networkInfo.canJoin = network.mt7902_joinable != 0
                result.insert(networkInfo)
            }

            DispatchQueue.main.async {
                let callbacks = scanCallbacks
                scanCallbacks.removeAll()
                callbacks.forEach { $0(result) }
            }
        }
    }

    static func scanSavedNetworks() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { scanSavedNetworks() }
            return
        }
        guard let token = autoJoinRequest.begin() else { return }
        DispatchQueue.global(qos: .background).async {
            let savedNetworks: [NetworkInfo] = CredentialsManager.instance.getSavedNetworks()
            DispatchQueue.main.async {
                guard !savedNetworks.isEmpty else { autoJoinRequest.finish(token); return }
                autoJoinTimer.start(interval: 5, immediately: true) {
                    guard !connectionRequest.isBusy, is_power_on() else { return }
                    NetworkManager.scanNetwork { networkList in
                        // Join the current driver observation, not a stripped/stale
                        // Keychain comment whose security may default to NONE.
                        let targets = NetworkInfo.currentJoinTargets(saved: savedNetworks, visible: networkList)
                        guard !targets.isEmpty else { return }
                        autoJoinTimer.stop()
                        autoJoinRequest.finish(token)
                        connectSavedNetworks(networks: targets)
                    }
                }
            }
        }
    }

    private static func connectSavedNetworks(networks: [NetworkInfo]) {
        guard !connectionRequest.isBusy, let first = networks.first else { return }
        guard joinSession.beginAutomaticJoin(first.ssid) else {
            connectSavedNetworks(networks: Array(networks.dropFirst()))
            return
        }
        connect(networkInfo: first, interactive: false) { connected in
            if !connected { connectSavedNetworks(networks: Array(networks.dropFirst())) }
        }
    }

    static func getMACAddressFromBSD(bsd: String) -> String? {
        InterfaceDetails.macAddress(bsd: bsd)
    }

    static func isReachable() -> Bool {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, "captive.apple.com") else {
            return false
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)

        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(reachability, &flags)

        let isReachable: Bool = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
        let canConnectWithoutUserInteraction = canConnectAutomatically && !flags.contains(.interventionRequired)
        return isReachable && (!needsConnection || canConnectWithoutUserInteraction)
    }

    static func getRouterAddress(bsd: String) -> String? {
        InterfaceDetails.routerAddress(bsd: bsd)
    }

    static func getLocalAddress(bsd: String) -> String? {
        InterfaceDetails.localAddress(bsd: bsd)
    }

    static func getSecurityType(_ info: ioctl_network_info) -> itl80211_security {
        return info.mt7902_security
    }
}
