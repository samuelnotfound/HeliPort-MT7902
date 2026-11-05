# HeliPort-MT7902 2.1.5

Stop repeated Mac login/Keychain authorization prompts during menu polling.
KeychainAccess.get(handler:) requests both attributes and the protected value;
menu rows now use an attributes-only SecItemCopyMatching query with authentication
UI disabled. Listing saved SSIDs no longer reads every network's password.
Legacy security-NONE comments are matched to current scan entries without secret
reads, preserving 2.1.4's saved-network selection correction.

Background auto-join never opens Keychain authorization or Wi-Fi password windows.
It tries each saved network once after a failure until an explicit user retry or
successful connection. Credentials authorized for a join are copied into a locked,
process-local session cache, so retrying does not repeatedly ask for the same
Keychain access. Forgetting a network clears that cache; quitting clears it all.
A failed connection keeps only that session copy; persistent password saving still
requires a successful connection and the user's Save selection.

Explicitly open scan entries bypass saved passwords even if an older protected
hotspot used the same SSID. Empty-password commands require driver 0.2.16; older
drivers continue to refuse them. Original UI, timers and ABI v1 are retained.

Regression tests inspect the real metadata-query keys (no ReturnData, no UI),
old-NONE/current-scan matching, cache isolation/security changes/forgetting,
concurrent cache access, bounded automatic attempts and open command encoding.
The Intel build also compiles the complete app against the pinned KeychainAccess.
Actual Keychain authorization and open-hotspot connectivity need macOS testing.

References:
- https://github.com/kishikawakatsumi/KeychainAccess/blob/e0c7eebc5a4465a3c4680764f26b7a61f567cdaf/Lib/KeychainAccess/Keychain.swift
- https://developer.apple.com/documentation/security/ksecreturndata
- https://developer.apple.com/documentation/security/ksecuseauthenticationuifail
