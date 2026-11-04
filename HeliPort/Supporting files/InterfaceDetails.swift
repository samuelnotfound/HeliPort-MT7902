// SPDX-License-Identifier: BSD-3-Clause
import Foundation
import SystemConfiguration

enum InterfaceDetails {
    static func macAddress(bsd: String) -> String? {
        guard !bsd.isEmpty, let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in interfaces where (SCNetworkInterfaceGetBSDName(interface) as String?) == bsd {
            return (SCNetworkInterfaceGetHardwareAddressString(interface) as String?)?.lowercased()
        }
        return nil
    }

    static func snapshot(bsd: String, entity: CFString) -> [String: Any]? {
        guard !bsd.isEmpty else { return nil }
        guard let key = SCDynamicStoreKeyCreateNetworkInterfaceEntity(nil, kSCDynamicStoreDomainState, bsd as CFString, entity) else { return nil }
        return SCDynamicStoreCopyValue(nil, key) as? [String: Any]
    }

    static func localAddress(bsd: String) -> String? {
        let entities: [CFString] = [kSCEntNetIPv4, kSCEntNetIPv6]
        for entity in entities {
            if let address = firstAddress(in: snapshot(bsd: bsd, entity: entity)) { return address }
        }
        return nil
    }

    static func routerAddress(bsd: String) -> String? {
        let entities: [CFString] = [kSCEntNetIPv4, kSCEntNetIPv6]
        for entity in entities {
            if let router = router(in: snapshot(bsd: bsd, entity: entity)) { return router }
        }
        return nil
    }

    static func firstAddress(in snapshot: [String: Any]?) -> String? {
        (snapshot?[kSCPropNetIPv4Addresses as String] as? [String])?.first(where: { !$0.isEmpty })
    }

    static func router(in snapshot: [String: Any]?) -> String? {
        guard let address = snapshot?[kSCPropNetIPv4Router as String] as? String, !address.isEmpty else { return nil }
        return address
    }
}
