# HeliPort MT7902

HeliPort's menu-bar UI adapted to the **standalone itlmt7902 Ethernet driver**.
This is a fork of [OpenIntelWireless/HeliPort](https://github.com/OpenIntelWireless/HeliPort),
not an official OpenIntelWireless release. UI, icons, keychain management,
preferences and original contributor notices are retained. See [LICENSE](LICENSE),
[NOTICE-MT7902.md](NOTICE-MT7902.md) and [original credits](docs/UPSTREAM-README.md).

Driver and installation: [samuelnotfound/itlmt7902-wifi](https://github.com/samuelnotfound/itlmt7902-wifi).

## Install

1. Install the standalone `itlmt7902.kext` using the driver repository's setup
   instructions, or keep your existing working installation. A new driver
   installation needs a reboot; replacing only this app does not.
2. Download the latest successful Actions artifact **HeliPort-MT7902**, unzip its
   inner `HeliPort-MT7902.zip`, and copy **HeliPort-MT7902.app** into `/Applications`.
3. Quit other Wi-Fi control apps and disable their login items so
   only one app manages connections. Open HeliPort-MT7902, pick your network and
   enter the password. Save it to the keychain if desired. The menu offers both
   modern and legacy HeliPort appearances through Preferences.
4. Keep your existing connection-mode configuration. If installing this driver
   fresh, its stage-3 connection test requires `mt7902_stage=3`.
   The app uses the existing ABI v1 and does not patch
   or install the driver.

The UI adapter is compile/fixture tested, **not yet hardware validated**. Known
hotspot connectivity belongs to the standalone driver, not to this new app.
Router interoperability is unchanged; this does not add WPA3, enterprise, open
networks, roaming, native Wi-Fi or faster PHY modes to the driver.

If the app reports scan-only stage 2, add `mt7902_stage=3` to your existing
OpenCore NVRAM `boot-args` and reboot once. Without this argument, the current
driver defaults to scanning only. Keep the menu open while a scan completes;
the app refreshes results in scan-only mode and after a failed connection.

## Behavior and limits

- Scan results and link/error state come from `itlmt7902` registry properties.
- Join/disconnect use its existing IOUserClient selectors. Passphrases are never
  passed to a shell, published to ioreg, logged or added to a kext plist.
- The Ethernet interface can be created only after connection. That is allowed
  at launch; the app no longer assumes a BSD interface must exist before joining.
- WPA2-PSK/CCMP and supported-channel decisions come from the driver. Unsupported
  networks are shown but refused instead of pretending the hardware supports them.
- BSSID/noise/MCS/PHY values not supplied by the existing driver show as unknown.
- The menu's power switch is a **software connection switch**. Off disconnects
  and prevents this app's joins; it does not power down the radio or kext.
- Automatic stock HeliPort updates are disabled so they cannot replace this
  adapter. This app has a separate bundle ID/keychain namespace.

## Build

On Intel macOS with Xcode installed:

```sh
bash scripts/build-macos.sh
```

This runs ABI/state/security/scan decoder fixtures with ASan/UBSan, builds the
original Xcode UI project with the app-only MT7902 C adapter, signs it ad hoc and
packages it with its license/notice. Dependencies are pinned in Package.resolved.
Output: `build/dist/HeliPort-MT7902.zip`. No kext is built, installed or loaded.

## App updates

Version **2.0.3** serializes the connection animation on the main run loop and
uses SystemConfiguration for interface details instead of unchecked route-buffer
parsing. The app's regression suite tests rapid start/stop transitions and missing
interface data. Replace only the app in `/Applications`; keep your installed kext.
