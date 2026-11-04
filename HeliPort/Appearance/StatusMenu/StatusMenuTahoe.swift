// SPDX-License-Identifier: BSD-3-Clause
import Cocoa

// Let AppKit render Tahoe's menu material, icon column, selection and section
// headers. Network rows use public NSMenuItem behavior, not custom hover views.
@available(macOS 26, *)
final class StatusMenuTahoe: StatusMenuBase, StatusMenuItems {
    private let headerView = StateSwitchMenuItemView(title: .Modern.wifi) { sender in
        _ = sender.state == .on ? power_on() : power_off()
    }
    private let connectedHeader = NSMenuItem.sectionHeader(title: NSLocalizedString("Connected", comment: "Connected network section"))
    private let connectedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let knownHeader = NSMenuItem.sectionHeader(title: .Modern.knownNetworks)
    private let otherHeader = NSMenuItem.sectionHeader(title: .Modern.otherNetworks)
    private let manualItem = NSMenuItem(title: .Modern.joinNetworks)
    private let settingsItem = NSMenuItem(title: .Modern.wifiSettings)
    private var knownItems = [NSMenuItem]()
    private var otherItems = [NSMenuItem]()
    private var connectedSSID: String?

    var enabledNetworkCardItems: [NSMenuItem] { [] }
    var stationInfoItems: [NSMenuItem] { [ipAddresssItem, routerItem, internetItem, channelItem, rssiItem, txRateItem] }
    var hiddenItems: [NSMenuItem] { [bsdItem, macItem, itlwmVerItem, createReportItem, hardwareInfoSeparator] }
    var notImplementedItems: [NSMenuItem] { [] }

    override init() {
        super.init()
        autoenablesItems = false
        minimumWidth = 320
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setupMenu() {
        let header = NSMenuItem()
        header.view = headerView
        headerView.isEnabled = true
        addItem(header)
        addItem(.separator())
        connectedHeader.isHidden = true
        connectedItem.isHidden = true
        connectedItem.target = self
        connectedItem.action = #selector(disconnectCurrent(_:))
        connectedItem.image = symbol("wifi")
        addItem(connectedHeader)
        addItem(connectedItem)
        for item in stationInfoItems {
            item.isEnabled = false
            item.representedObject = item.title
            addItem(item)
        }
        knownHeader.isHidden = true
        otherHeader.isHidden = true
        addItem(knownHeader)
        addItem(otherHeader)
        manualItem.image = symbol("plus")
        addClickItem(manualItem)
        addItem(.separator())
        settingsItem.image = symbol("gearshape")
        addClickItem(settingsItem)
        toggleLaunchItem.image = symbol("power")
        addClickItem(toggleLaunchItem)
        aboutItem.image = symbol("info.circle")
        addClickItem(aboutItem)
        addClickItem(quitItem)
        for item in [bsdItem, macItem, itlwmVerItem] {
            item.isEnabled = false
            item.representedObject = item.title
            addItem(item)
        }
        addItem(hardwareInfoSeparator)
        addClickItem(createReportItem)
    }

    func setValueForItem(_ item: NSMenuItem, value: String) {
        let key = item.representedObject as? String ?? item.title
        item.representedObject = key
        item.title = key + " " + value
    }

    override var isNetworkCardAvailable: Bool {
        didSet { headerView.isEnabled = isNetworkCardAvailable }
    }

    override var isNetworkCardEnabled: Bool {
        didSet {
            headerView.state = isNetworkCardEnabled
            manualItem.isEnabled = isNetworkCardEnabled
            if !isNetworkCardEnabled {
                connectedSSID = nil
                connectedHeader.isHidden = true
                connectedItem.isHidden = true
                knownHeader.isHidden = true
                otherHeader.isHidden = true
                (knownItems + otherItems).forEach { $0.isHidden = true }
            }
        }
    }

    func toggleWIFI() { DispatchQueue.main.async { self.headerView.toggle() } }

    override func setCurrentNetworkItem(with info: StatusMenuBase.StationInfo) {
        isNetworkConnected = info.isNetworkConnected
        connectedSSID = info.isNetworkConnected ? info.ssid : nil
        connectedHeader.isHidden = !info.isNetworkConnected
        connectedItem.isHidden = !info.isNetworkConnected
        connectedItem.title = info.ssid ?? ""
        connectedItem.state = info.isNetworkConnected ? .on : .off
        connectedItem.toolTip = "\(info.rssiValue) dBm"
    }

    func updateNetworkList() {
        guard isNetworkCardEnabled else { return }
        NetworkManager.scanNetwork { known, other in
            guard self.isNetworkCardEnabled else { return }
            for item in self.knownItems + self.otherItems { self.removeItem(item) }
            self.knownItems.removeAll()
            self.otherItems.removeAll()
            let visibleKnown = known.filter { $0.ssid != self.connectedSSID }
            let visibleOther = other.filter { $0.ssid != self.connectedSSID }
            self.knownHeader.isHidden = visibleKnown.isEmpty
            self.otherHeader.isHidden = visibleOther.isEmpty
            for network in visibleKnown {
                let item = self.networkItem(network)
                self.insertItem(item, at: self.index(of: self.otherHeader))
                self.knownItems.append(item)
            }
            for network in visibleOther {
                let item = self.networkItem(network)
                self.insertItem(item, at: self.index(of: self.manualItem))
                self.otherItems.append(item)
            }
        }
    }

    private func networkItem(_ network: NetworkInfo) -> NSMenuItem {
        let item = NSMenuItem(title: network.ssid, action: #selector(joinNetwork(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = network
        item.image = symbol("wifi")
        item.isEnabled = network.canJoin != false && NetworkManager.supportedSecurityMode.contains(network.auth.security)
        item.toolTip = "\(network.auth.security.description) · \(network.rssi) dBm"
        if network.auth.security != ITL80211_SECURITY_NONE {
            let title = NSMutableAttributedString(string: network.ssid + "  ")
            let lock = NSTextAttachment()
            lock.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: NSLocalizedString("Password protected", comment: "Secured network"))
            lock.bounds = NSRect(x: 0, y: 0, width: 9, height: 10)
            title.append(NSAttributedString(attachment: lock))
            item.attributedTitle = title
        }
        return item
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    @objc private func joinNetwork(_ sender: NSMenuItem) {
        guard let network = sender.representedObject as? NetworkInfo else { return }
        cancelTracking()
        NetworkManager.connect(networkInfo: network, saveNetwork: true)
    }

    @objc private func disconnectCurrent(_ sender: NSMenuItem) {
        let ssid = connectedSSID
        cancelTracking()
        DispatchQueue.global(qos: .userInitiated).async {
            if let ssid { CredentialsManager.instance.setAutoJoin(ssid, false) }
            _ = dis_associate_ssid(ssid ?? "")
        }
    }
}
