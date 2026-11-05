# HeliPort-MT7902 2.1.4

Correct saved-network security metadata and auto-join selection. The previous
save path reset the live request's auth object, persisted security NONE in the
Keychain comment, then auto-join rejected that comment before loading the actual
WPA2 credentials. This can produce "Network security not supported: None".

Save an independent metadata snapshot that preserves the security mode and
excludes passwords, usernames and identity bytes. Existing saved entries recover
the mode from the protected Keychain value in memory. Auto-join uses the current
joinable driver observation, in saved priority order, instead of stale metadata.
No password deletion or re-entry is required for migration.

The original UI, work gates, timers and kernel ABI stay unchanged. Existing
lifecycle tests also verify metadata isolation, credential-free serialization
and selection from old NONE metadata. This app correction does not establish
that router authentication works; the driver is tested separately.
