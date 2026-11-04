//
//  StatusBarIconManager.swift
//  HeliPort
//
//  Created by 梁怀宇 on 2020/4/7.
//  Copyright © 2020 OpenIntelWireless. All rights reserved.
//

/*
 * This program and the accompanying materials are licensed and made available
 * under the terms and conditions of the The 3-Clause BSD License
 * which accompanies this distribution. The full text of the license may be found at
 * https://opensource.org/licenses/BSD-3-Clause
 */

import Cocoa

protocol StatusBarIconProvider {
    var transition: CATransition? { get }
    var off: NSImage { get }
    var connected: NSImage { get }
    var disconnected: NSImage { get }
    var warning: NSImage { get }
    var scanning: [NSImage] { get }
    func getRssiImage(_ RSSI: Int16) -> NSImage?
}

class StatusBarIcon {
    private static var instance: StatusBarIcon?

    private let statusBar: NSStatusItem
    private let icons: StatusBarIconProvider
    private let animation: ConnectionAnimation

    private init(_ statusBar: NSStatusItem, _ icons: StatusBarIconProvider) {
        self.statusBar = statusBar
        self.icons = icons
        self.animation = ConnectionAnimation(frameCount: { icons.scanning.count }, render: { index in
            let frames = icons.scanning
            guard frames.indices.contains(index) else { return }
            if let transition = icons.transition {
                statusBar.button?.layer?.add(transition, forKey: kCATransition)
            }
            statusBar.button?.image = frames[index]
        })
    }

    static func shared(statusBar: NSStatusItem? = nil, icons: StatusBarIconProvider? = nil) -> StatusBarIcon {
        if let instance {
            return instance
        }
        guard let statusBar, let icons else {
            fatalError("Must provide statusBar and iconProvider for the first initialization.")
        }
        let created = StatusBarIcon(statusBar, icons)
        instance = created
        return created
    }

    func on() {
        disconnected()
    }

    func off() {
        setImage { self.icons.off }
    }

    func connected() {
        setImage { self.icons.connected }
    }

    func disconnected() {
        setImage { self.icons.disconnected }
    }

    func connecting() {
        animation.start()
    }

    func warning() {
        setImage { self.icons.warning }
    }

    func error() {
        setImage { #imageLiteral(resourceName: "WiFiStateError") }
    }

    func signalStrength(rssi: Int16) {
        setImage { self.icons.getRssiImage(rssi) }
    }

    func getRssiImage(rssi: Int16) -> NSImage? {
        return icons.getRssiImage(rssi)
    }

    private func setImage(_ image: @escaping () -> NSImage?) {
        let update = {
            self.animation.stop()
            self.statusBar.button?.image = image()
        }
        if Thread.isMainThread { update() }
        else { DispatchQueue.main.async(execute: update) }
    }
}
