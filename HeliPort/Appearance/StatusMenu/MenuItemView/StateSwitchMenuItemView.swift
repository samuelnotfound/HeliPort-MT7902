//
//  StateSwitchMenuItemView.swift
//  HeliPort
//
//  Created by Bat.bat on 22/6/2024.
//  Copyright © 2024 OpenIntelWireless. All rights reserved.
//

/*
 * This program and the accompanying materials are licensed and made available
 * under the terms and conditions of the The 3-Clause BSD License
 * which accompanies this distribution. The full text of the license may be found at
 * https://opensource.org/licenses/BSD-3-Clause
 */

import Cocoa

@available(macOS 11, *)
class StateSwitchMenuItemView: NSView {

    // MARK: Initializers

    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
        label.textColor = .controlTextColor
        return label
    }()

    private let stateSwitch = NSSwitch()
    private let actionClosure: ((NSSwitch) -> Void)

    init(title: String, action: @escaping (NSSwitch) -> Void) {
        actionClosure = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(stateSwitch)

        label.stringValue = title
        if #available(macOS 26, *) {
            label.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
            stateSwitch.controlSize = .large
        }
        stateSwitch.action = #selector(switchValueDidChange)
        stateSwitch.target = self

        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    public var state: Bool = false {
        willSet(state) {
            stateSwitch.state = state ? .on : .off
        }
    }

    public var isEnabled: Bool = false {
        willSet {
            stateSwitch.isEnabled = newValue
        }
    }

    public func toggle() {
        stateSwitch.performClick(self)
    }

    // MARK: Private

    private func setupLayout() {
        self.subviews.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        let rowHeight: CGFloat
        if #available(macOS 26, *) { rowHeight = 48 }
        else { rowHeight = NSMenuItem.ItemHeight.networkModern.rawValue }
        let heightConstraint = heightAnchor.constraint(equalToConstant: rowHeight)
        heightConstraint.priority = NSLayoutConstraint.Priority(1000)
        heightConstraint.isActive = true

        label.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14).isActive = true

        stateSwitch.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        stateSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14).isActive = true
        label.trailingAnchor.constraint(lessThanOrEqualTo: stateSwitch.leadingAnchor, constant: -12).isActive = true
        if #unavailable(macOS 26) {
            stateSwitch.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
    }

    @objc private func switchValueDidChange(sender: NSSwitch) {
        actionClosure(sender)
    }
}
