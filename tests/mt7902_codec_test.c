// SPDX-License-Identifier: BSD-3-Clause
#include "../ClientKit/MT7902Codec.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    struct mt7902_join j;
    assert(mt7902_encode_join(&j, "test", "12345678"));
    assert(j.version == 1 && sizeof(j) == 108 && !strcmp(j.ssid, "test") && !strcmp(j.passphrase, "12345678"));
    assert(!mt7902_encode_join(&j, "", "12345678"));
    assert(!mt7902_encode_join(&j, "test", "1234567"));
    assert(!mt7902_encode_join(&j, "123456789012345678901234567890123", "12345678"));
    char ssid[33], key[64]; memset(ssid, 's', 32); ssid[32] = 0; memset(key, 'p', 63); key[63] = 0;
    assert(mt7902_encode_join(&j, ssid, key)); assert(j.ssid[32] == 0 && j.passphrase[63] == 0);
    assert(mt7902_state("connected") == ITL80211_S_RUN);
    assert(mt7902_state("connecting") == ITL80211_S_AUTH);
    assert(mt7902_state("failed") == ITL80211_S_INIT);
    assert(mt7902_should_refresh_scan(true, true, "idle"));
    assert(mt7902_should_refresh_scan(true, true, "scan-ready"));
    assert(mt7902_should_refresh_scan(true, true, "failed"));
    assert(!mt7902_should_refresh_scan(true, true, "connected"));
    assert(!mt7902_should_refresh_scan(true, true, "connecting"));
    assert(!mt7902_should_refresh_scan(true, true, "scanning"));
    assert(!mt7902_should_refresh_scan(false, true, "idle"));
    assert(!mt7902_should_refresh_scan(true, false, "scan-ready"));
    assert(!mt7902_should_refresh_scan(true, true, NULL));
    assert(mt7902_security("wpa2/wpa3") == ITL80211_SECURITY_WPA2_PERSONAL);
    assert(mt7902_security("enterprise") == ITL80211_SECURITY_WPA2_ENTERPRISE);
    assert(mt7902_security("unexpected") == ITL80211_SECURITY_UNKNOWN);
    int64_t raw = 4294967241LL, channel = 44;
    CFNumberRef rssi = CFNumberCreate(NULL, kCFNumberSInt64Type, &raw);
    CFNumberRef ch = CFNumberCreate(NULL, kCFNumberSInt64Type, &channel);
    const void *keys[] = {CFSTR("ssid"), CFSTR("security"), CFSTR("rssi"), CFSTR("channel"), CFSTR("joinable")};
    const void *values[] = {CFSTR("fixture"), CFSTR("wpa2"), rssi, ch, kCFBooleanTrue};
    CFDictionaryRef d = CFDictionaryCreate(NULL, keys, values, 5, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    struct ioctl_network_info n;
    assert(mt7902_decode_network(d, &n));
    assert(n.rssi == -55 && n.channel == 44 && n.mt7902_joinable == 1);
    assert(n.mt7902_security == ITL80211_SECURITY_WPA2_PERSONAL && !memcmp(n.ssid, "fixture", 7));
    assert(!mt7902_decode_network((CFDictionaryRef)CFSTR("malformed"), &n));
    assert(!mt7902_decode_network(NULL, &n));
    CFRelease(d); CFRelease(rssi); CFRelease(ch);
    puts("Passed MT7902 command ABI, scan refresh policy, bounds, state/security and signed scan decoding fixtures");
}
