//
//  NetworkManager+Data.swift
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
import Security

final class NetworkInfo: Codable {
    let ssid: String
    var rssi: Int
    var canJoin: Bool?

    var auth = NetworkAuth()

    init (ssid: String, rssi: Int = 0) {
        self.ssid = ssid
        self.rssi = rssi
    }
    static func currentJoinTargets(saved: [NetworkInfo], visible: Set<NetworkInfo>) -> [NetworkInfo] {
        saved.compactMap { remembered in
            visible.first { $0.ssid == remembered.ssid && $0.canJoin == true }
        }
    }

    // Public metadata may be stored in a Keychain comment. Credentials stay in
    // its protected value, and joinability must be refreshed from the driver.
    func storageSnapshot() -> NetworkInfo {
        let copy = NetworkInfo(ssid: ssid, rssi: rssi)
        copy.auth.security = auth.security
        return copy
    }

}

extension NetworkInfo: Hashable {
    static func == (lhs: NetworkInfo, rhs: NetworkInfo) -> Bool {
        return lhs.ssid == rhs.ssid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ssid)
    }
}

final class NetworkAuth: Codable {
    var security: itl80211_security = ITL80211_SECURITY_NONE
    var option: UInt64 = 0
    var identity = [UInt8]()
    var username: String = ""
    var password: String = ""
}

final class NetworkInfoStorageEntity: Codable {
    static let CURRENT_VERSION: UInt = 2

    var version: UInt = CURRENT_VERSION
    var autoJoin: Bool = true
    var order: Int = 0
    var network: NetworkInfo

    init (_ network: NetworkInfo, _ autoJoin: Bool = true, _ order: Int = 0) {
        self.network = network
        self.autoJoin = autoJoin
        self.order = order
    }
}

// Process-local snapshots: retries never re-authorize the same password, and a
// failed background join is attempted once until the user retries or it succeeds.
final class JoinSession {
    private let lock = NSLock()
    private var authBySSID = [String: NetworkAuth]()
    private var attempted = Set<String>()
    func remember(_ network: NetworkInfo, auth: NetworkAuth) {
        lock.lock(); defer { lock.unlock() }
        let copy = NetworkAuth()
        copy.security = auth.security; copy.password = auth.password
        authBySSID[network.ssid] = copy
        attempted.insert(network.ssid)
    }
    func credentials(for network: NetworkInfo) -> NetworkAuth? {
        lock.lock(); defer { lock.unlock() }
        guard let saved = authBySSID[network.ssid], saved.security == network.auth.security else { return nil }
        let copy = NetworkAuth()
        copy.security = saved.security; copy.password = saved.password
        return copy
    }
    func beginAutomaticJoin(_ ssid: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return attempted.insert(ssid).inserted
    }
    func succeeded(_ ssid: String) {
        lock.lock(); defer { lock.unlock() }
        attempted.remove(ssid)
    }
    func forget(_ ssid: String) {
        lock.lock(); defer { lock.unlock() }
        authBySSID.removeValue(forKey: ssid); attempted.remove(ssid)
    }
}

// Listing SSIDs/security must never request password data or show authorization UI.
enum SavedNetworkMetadata {
    static func query(service: String, ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: ssid,
         kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
         kSecMatchLimit as String: kSecMatchLimitOne,
         kSecReturnAttributes as String: true,
         kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    }
}
