// SPDX-License-Identifier: BSD-3-Clause
import Foundation

enum MenuAppearance: String {
    case legacy, modern, tahoe

    static func select(osMajor: Int, legacyRequested: Bool) -> MenuAppearance {
        if legacyRequested || osMajor < 11 { return .legacy }
        return osMajor >= 26 ? .tahoe : .modern
    }
}
