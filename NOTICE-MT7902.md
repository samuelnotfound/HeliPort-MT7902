# HeliPort MT7902 fork

The menu/UI, saved-network/keychain management, icons and supporting application
code come from OpenIntelWireless/HeliPort commit
`898bcd8366844fdcfe047d7ebdf90631e4642b66`, under the retained BSD-3-Clause
LICENSE and file-specific notices. The original contributors' credits are retained
in docs/UPSTREAM-README.md. This fork is not an official OpenIntelWireless release.

ClientKit/MT7902.c and MT7902Codec.h replace the app's compiled Intel ioctl transport
with standalone itlmt7902 IOUserClient ABI v1 and registry snapshots. The original
Api.c remains as upstream history/source reference but is not compiled by the app.

This app does not bundle or change a kernel extension. The standalone MT7902
driver is separately maintained in samuelnotfound/itlmt7902-wifi. Driver protocols
and behavior derive from the MediaTek sources documented there. This app cannot
add unsupported security modes, fix router interoperability or provide native Wi-Fi.
