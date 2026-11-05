//
//  CredentialsManager.swift
//  HeliPort
//
//  Created by Igor Kulman on 22/06/2020.
//  Copyright © 2020 OpenIntelWireless. All rights reserved.
//

/*
 * This program and the accompanying materials are licensed and made available
 * under the terms and conditions of the The 3-Clause BSD License
 * which accompanies this distribution. The full text of the license may be found at
 * https://opensource.org/licenses/BSD-3-Clause
 */

import Foundation
import KeychainAccess
import Security

final class CredentialsManager {
    static let instance: CredentialsManager = CredentialsManager()

    private let keychain: Keychain
    private let ssidCache: NSCache = NSCache<NSString, NSSet>()
    private let ssidCacheKey = NSString("savedSSIDs")

    private init() {
        keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    }

    func save(_ network: NetworkInfo) {
        guard let networkAuthJson = try? String(decoding: JSONEncoder().encode(network.auth), as: UTF8.self) else {
            return
        }
        // The Keychain value owns credentials; its comment retains non-secret
        // security metadata. Never clear auth on a request referenced by the UI.
        let entity = NetworkInfoStorageEntity(network.storageSnapshot())
        guard let entityJson = try? String(decoding: JSONEncoder().encode(entity), as: UTF8.self) else {
            return
        }

        ssidCache.removeObject(forKey: ssidCacheKey)

        Log.debug("Saving password for network \(network.ssid)")
        try? keychain.comment(entityJson).set(networkAuthJson, key: network.keychainKey)
    }

    func get(_ network: NetworkInfo, interactive: Bool = true) -> NetworkAuth? {
        guard let password = try? keychain.authenticationUI(interactive ? .allow : .fail).getString(network.keychainKey),
            let jsonData = password.data(using: .utf8) else {
            Log.debug("No stored password for network \(network.ssid)")
            return nil
        }

        Log.debug("Loading password for network \(network.ssid)")
        return try? JSONDecoder().decode(NetworkAuth.self, from: jsonData)
    }

    func remove(_ network: NetworkInfo) {
        Log.debug("Removing \(network.ssid) from keychain")
        NetworkManager.joinSession.forget(network.ssid)
        ssidCache.removeObject(forKey: ssidCacheKey)
        try? keychain.remove(network.keychainKey)
    }

    func getStorageFromSsid(_ ssid: String) -> NetworkInfoStorageEntity? {
        // KeychainAccess.get(handler:) also requests kSecReturnData. Menu
        // refreshes only need the public comment, never password authorization.
        let query = SavedNetworkMetadata.query(service: Bundle.main.bundleIdentifier!, ssid: ssid)
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any],
              let json = attributes[kSecAttrComment as String] as? String,
              let jsonData = json.data(using: .utf8) else { return nil }

        return try? JSONDecoder().decode(NetworkInfoStorageEntity.self, from: jsonData)
    }

    func getAuthFromSsid(_ ssid: String) -> NetworkAuth? {
        return get(NetworkInfo(ssid: ssid), interactive: false)
    }

    func setAutoJoin(_ ssid: String, _ autoJoin: Bool) {
        guard let entity = getStorageFromSsid(ssid),
            let auth = getAuthFromSsid(ssid) else {
                return
        }

        entity.autoJoin = autoJoin

        guard let entityJson = try? String(decoding: JSONEncoder().encode(entity), as: UTF8.self),
              let authJson = try? String(decoding: JSONEncoder().encode(auth), as: UTF8.self) else {
            return
        }

        try? keychain.comment(entityJson).set(authJson, key: ssid)
    }

    func setPriority(_ ssid: String, _ priority: Int) {
        guard let entity = getStorageFromSsid(ssid),
            let auth = getAuthFromSsid(ssid) else {
                return
        }

        entity.order = priority

        guard let entityJson = try? String(decoding: JSONEncoder().encode(entity), as: UTF8.self),
              let authJson = try? String(decoding: JSONEncoder().encode(auth), as: UTF8.self) else {
            return
        }

        try? keychain.comment(entityJson).set(authJson, key: ssid)
    }

    func getSavedNetworks() -> [NetworkInfo] {
        return (keychain.allKeys().compactMap { ssid in
            return getStorageFromSsid(ssid)
        } as [NetworkInfoStorageEntity]).filter { entity in
            entity.autoJoin && entity.version == NetworkInfoStorageEntity.CURRENT_VERSION
        }.sorted {
            $0.order < $1.order
        }.map { $0.network.storageSnapshot() }
        // Auto-join matches these SSIDs to current scan entries. Legacy NONE
        // comments do not require loading every protected password to repair.
    }

    func getSavedNetworkSSIDs() -> Set<String> {
        if let cached = ssidCache.object(forKey: ssidCacheKey) as? Set<String> {
            return cached
        }
        let savedSSIDs = Set(keychain.allKeys())
        ssidCache.setObject(savedSSIDs as NSSet, forKey: ssidCacheKey)
        return savedSSIDs
    }

    func getSavedNetworksEntity() -> [NetworkInfoStorageEntity] {
        return (keychain.allKeys().compactMap { ssid in
            return getStorageFromSsid(ssid)
        } as [NetworkInfoStorageEntity]).filter { entity in
            entity.version == NetworkInfoStorageEntity.CURRENT_VERSION
        }.sorted {
            $0.order < $1.order
        }.map { entity in
            guard let auth = getAuthFromSsid(entity.network.ssid) else {
                return entity
            }
            entity.network.auth = auth
            return entity
        }
    }
}

fileprivate extension NetworkInfo {
    var keychainKey: String {
        return ssid
    }
}
