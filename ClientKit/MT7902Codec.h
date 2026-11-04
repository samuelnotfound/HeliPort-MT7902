// SPDX-License-Identifier: BSD-3-Clause
// App-side translation for the existing standalone itlmt7902 ABI; no kernel code.
#pragma once
#include "Api.h"
#include <CoreFoundation/CoreFoundation.h>

struct mt7902_join { uint32_t version; char ssid[36]; char passphrase[68]; };
_Static_assert(sizeof(struct mt7902_join) == 108, "itlmt7902 join ABI");
static inline bool mt7902_encode_join(struct mt7902_join *out, const char *ssid, const char *password) {
    memset(out, 0, sizeof(*out));
    if (!ssid || !password) return false;
    size_t sn = strnlen(ssid, 33), pn = strnlen(password, 64);
    if (!sn || sn > 32 || pn < 8 || pn > 63) return false;
    out->version = 1; memcpy(out->ssid, ssid, sn); memcpy(out->passphrase, password, pn);
    return true;
}
static inline uint32_t mt7902_state(const char *s) {
    if (!strcmp(s, "connected")) return ITL80211_S_RUN;
    if (!strcmp(s, "connecting")) return ITL80211_S_AUTH;
    if (!strcmp(s, "scanning")) return ITL80211_S_SCAN;
    return ITL80211_S_INIT;
}
static inline bool mt7902_string(CFTypeRef v, char *out, size_t capacity) {
    if (!capacity) return false;
    out[0] = 0;
    return v && CFGetTypeID(v) == CFStringGetTypeID() &&
        CFStringGetCString((CFStringRef)v, out, (CFIndex)capacity, kCFStringEncodingUTF8);
}
static inline int32_t mt7902_number(CFTypeRef v) {
    int64_t n = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberSInt64Type, &n);
    return (int32_t)(uint32_t)n; // ioreg encodes the signed RSSI in an unsigned 32-bit OSNumber
}
static inline enum itl80211_security mt7902_security(const char *s) {
    if (!strcmp(s, "open")) return ITL80211_SECURITY_NONE;
    if (!strcmp(s, "wep")) return ITL80211_SECURITY_WEP;
    if (!strcmp(s, "wpa")) return ITL80211_SECURITY_WPA_PERSONAL;
    if (!strcmp(s, "wpa2") || !strcmp(s, "wpa2/wpa3")) return ITL80211_SECURITY_WPA2_PERSONAL;
    if (!strcmp(s, "wpa3")) return ITL80211_SECURITY_WPA3_PERSONAL;
    if (!strcmp(s, "enterprise")) return ITL80211_SECURITY_WPA2_ENTERPRISE;
    return ITL80211_SECURITY_UNKNOWN;
}
static inline bool mt7902_decode_network(CFDictionaryRef d, struct ioctl_network_info *out) {
    memset(out, 0, sizeof(*out));
    if (!d || CFGetTypeID(d) != CFDictionaryGetTypeID()) return false;
    char ssid[33], security[32];
    if (!mt7902_string(CFDictionaryGetValue(d, CFSTR("ssid")), ssid, sizeof(ssid)) || !ssid[0]) return false;
    memcpy(out->ssid, ssid, strlen(ssid));
    out->channel = (uint32_t)mt7902_number(CFDictionaryGetValue(d, CFSTR("channel")));
    out->rssi = (int16_t)mt7902_number(CFDictionaryGetValue(d, CFSTR("rssi")));
    mt7902_string(CFDictionaryGetValue(d, CFSTR("security")), security, sizeof(security));
    out->mt7902_security = mt7902_security(security);
    out->mt7902_joinable = CFDictionaryGetValue(d, CFSTR("joinable")) == kCFBooleanTrue;
    // No fake BSSID, noise or PHY capabilities: the existing driver's scan dictionary does not expose these.
    return true;
}
