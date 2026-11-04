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
import SystemConfiguration

final class NetworkManager {
    static let supportedSecurityMode = [
        ITL80211_SECURITY_WPA2_PERSONAL
    ]

    static func connect(networkInfo: NetworkInfo, saveNetwork: Bool = false,
                        _ callback: ((_ result: Bool) -> Void)? = nil) {

        guard networkInfo.canJoin != false else {
            Alert(text: "This network is not joinable by the current MT7902 driver (WPA2-PSK/CCMP, optional PMF, supported channels only).").show()
            callback?(false)
            return
        }

        guard supportedSecurityMode.contains(networkInfo.auth.security) else {
            let alert = Alert(text: NSLocalizedString("Network security not supported: ")
                              + networkInfo.auth.security.description)
            alert.show()
            callback?(false)
            return
        }

        let getAuthInfoCallback: (_ auth: NetworkAuth, _ savePassword: Bool) -> Void = { auth, savePassword in
            DispatchQueue.global(qos: .background).async {
                StatusBarIcon.shared().connecting()
                let result = connect_network(networkInfo.ssid, auth.password)
                DispatchQueue.main.async {
                    if result {
                        if savePassword {
                            CredentialsManager.instance.save(networkInfo)
                        }
                    } else {
                        Log.error("Failed to connect to: \(networkInfo.ssid)")
                        var error = [CChar](repeating: 0, count: 256)
                        mt7902_copy_error(&error, error.count)
                        let detail = String(cString: error)
                        Alert(text: detail.isEmpty ? "The MT7902 driver could not join this network." : detail).show()
                    }
                    callback?(result)
                }
            }
        }

        // Getting keychain access blocks UI Thread and makes everything freeze unless made async
        DispatchQueue.global().async {
            if let savedNetworkAuth = CredentialsManager.instance.get(networkInfo) {
                networkInfo.auth = savedNetworkAuth
                Log.debug("Connecting to network \(networkInfo.ssid) with saved password")
                CredentialsManager.instance.setAutoJoin(networkInfo.ssid, true)
                getAuthInfoCallback(networkInfo.auth, false)
                return
            }

            guard networkInfo.auth.security != ITL80211_SECURITY_NONE,
                  networkInfo.auth.password.isEmpty else {
                getAuthInfoCallback(networkInfo.auth, saveNetwork)
                return
            }

            DispatchQueue.main.async {
                WiFiConfigWindow(windowState: .connectWiFi,
                                 networkInfo: networkInfo,
                                 getAuthInfoCallback: getAuthInfoCallback).show()
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
                callback(result)
            }
        }
    }

    static func scanSavedNetworks() {
        DispatchQueue.global(qos: .background).async {
            let savedNetworks: [NetworkInfo] = CredentialsManager.instance.getSavedNetworks()
            guard savedNetworks.count > 0 else {
                Log.debug("No network saved for auto join")
                return
            }
            let scanTimer: Timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { timer in
                NetworkManager.scanNetwork { networkList in
                    let targetNetworks = savedNetworks.filter { networkList.contains($0) }
                    if targetNetworks.count > 0 {
                        // This will stop the timer completely
                        timer.invalidate()
                        Log.debug("Auto join timer stopped")
                        connectSavedNetworks(networks: targetNetworks)
                    }
                }
            }
            // Start executing code inside the timer immediately
            scanTimer.fire()
            let currentRunLoop = RunLoop.current
            currentRunLoop.add(scanTimer, forMode: .common)
            currentRunLoop.run()
        }
    }

    private static func connectSavedNetworks(networks: [NetworkInfo]) {
        DispatchQueue.global(qos: .background).async {
            let dispatchSemaphore = DispatchSemaphore(value: 0)
            var connected = false
            for network in networks where !connected {
                connect(networkInfo: network) { (result: Bool) in
                    connected = result
                    dispatchSemaphore.signal()
                }
                dispatchSemaphore.wait()
            }
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
