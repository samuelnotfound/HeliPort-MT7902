// SPDX-License-Identifier: BSD-3-Clause
// HeliPort UI adapter for standalone itlmt7902. Only app code changes; the kext ABI is unchanged.
#include "MT7902Codec.h"
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <limits.h>

static pthread_mutex_t api_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool user_enabled = true;
static io_service_t service(void) { return IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("itlmt7902")); }
static CFTypeRef property(io_service_t s, CFStringRef key) {
    return IORegistryEntryCreateCFProperty(s, key, kCFAllocatorDefault, 0);
}
static bool string_property(io_service_t s, CFStringRef key, char *out, size_t size) {
    CFTypeRef v = property(s, key); bool ok = mt7902_string(v, out, size); if (v) CFRelease(v); return ok;
}
static int32_t number_property(io_service_t s, CFStringRef key) {
    CFTypeRef v = property(s, key); int32_t n = mt7902_number(v); if (v) CFRelease(v); return n;
}
static bool bool_property(io_service_t s, CFStringRef key) {
    CFTypeRef v = property(s, key); bool b = v == kCFBooleanTrue; if (v) CFRelease(v); return b;
}
static bool enabled(void) {
    pthread_mutex_lock(&api_mutex); bool on = user_enabled; pthread_mutex_unlock(&api_mutex); return on;
}
static void set_enabled(bool on) {
    pthread_mutex_lock(&api_mutex); user_enabled = on; pthread_mutex_unlock(&api_mutex);
}
bool open_adapter(io_connect_t *connection) {
    *connection = IO_OBJECT_NULL;
    io_service_t s = service(); if (!s) return false;
    kern_return_t r = IOServiceOpen(s, mach_task_self(), 0, connection); IOObjectRelease(s);
    return r == KERN_SUCCESS;
}
void close_adapter(io_connect_t c) { if (c) IOServiceClose(c); }
static kern_return_t command(uint32_t selector, const void *bytes, size_t size) {
    io_connect_t c; if (!open_adapter(&c)) return kIOReturnNotFound;
    kern_return_t r = IOConnectCallStructMethod(c, selector, bytes, size, NULL, NULL);
    close_adapter(c); return r;
}
void mt7902_copy_error(char *out, size_t capacity) {
    if (!capacity) return;
    io_service_t s = service(); out[0] = 0;
    if (!s) { strlcpy(out, "itlmt7902 is not loaded. Restore the standalone Ethernet driver.", capacity); return; }
    string_property(s, CFSTR("wifi-error"), out, capacity);
    if (!bool_property(s, CFSTR("join-supported"))) {
        if (number_property(s, CFSTR("diagnostic-stage")) == 2)
            strlcpy(out, "The driver is in scan-only stage 2. Add mt7902_stage=3 to OpenCore boot-args and reboot to enable connections.", capacity);
        else if (!out[0])
            strlcpy(out, "The driver has not enabled connections. Check the driver initialization log and diagnostic-stage in ioreg.", capacity);
    }
    IOObjectRelease(s);
}
bool get_platform_info(platform_info_t *out) {
    struct ioctl_driver_info d;
    if (ioctl_get(IOCTL_80211_DRIVER_INFO, &d, sizeof(d))) return false;
    memset(out, 0, sizeof(*out));
    strlcpy(out->device_info_str, d.bsd_name, sizeof(out->device_info_str));
    strlcpy(out->driver_info_str, d.driver_version, sizeof(out->driver_info_str));
    return true;
}
bool get_power_state(bool *on) {
    io_service_t s = service(); if (!s) { *on = false; return false; }
    IOObjectRelease(s); *on = enabled(); return true;
}
bool is_power_on(void) { bool on = false; get_power_state(&on); return on; }
kern_return_t power_on(void) { set_enabled(true); return KERN_SUCCESS; }
kern_return_t power_off(void) {
    kern_return_t r = command(2, NULL, 0);
    if (r == KERN_SUCCESS) set_enabled(false);
    return r; // software off = leave network/stop app joins, not a hardware RF kill
}
bool get_80211_state(uint32_t *out) {
    io_service_t s = service(); if (!s) return false;
    char state[32]; bool ok = string_property(s, CFSTR("wifi-state"), state, sizeof(state));
    IOObjectRelease(s); *out = enabled() ? mt7902_state(state) : ITL80211_S_INIT; return ok;
}
bool get_network_ssid(char *out) {
    char ssid[33]; io_service_t s = service(); if (!s) return false;
    bool ok = string_property(s, CFSTR("wifi-ssid"), ssid, sizeof(ssid));
    IOObjectRelease(s); memset(out, 0, MAX_SSID_LENGTH); if (ok) memcpy(out, ssid, strlen(ssid)); return ok;
}
bool get_network_bssid(char *out) { memset(out, 0, ETHER_ADDR_LEN); return false; }
kern_return_t get_station_info(station_info_t *out) {
    memset(out, 0, sizeof(*out)); out->version = IOCTL_VERSION;
    io_service_t s = service(); if (!s) return kIOReturnNotFound;
    char ssid[33], state[32];
    string_property(s, CFSTR("wifi-state"), state, sizeof(state));
    if (!enabled() || strcmp(state, "connected")) { IOObjectRelease(s); return kIOReturnNotReady; }
    string_property(s, CFSTR("wifi-ssid"), ssid, sizeof(ssid)); memcpy(out->ssid, ssid, strlen(ssid));
    out->channel = (uint32_t)number_property(s, CFSTR("wifi-channel"));
    out->rssi = (int16_t)number_property(s, CFSTR("wifi-rssi"));
    out->rate = (uint32_t)number_property(s, CFSTR("wifi-rate"));
    out->band_width = 20; out->op_mode = (enum itl_phy_mode)255;
    out->cur_mcs = out->max_mcs = -1;
    IOObjectRelease(s); return KERN_SUCCESS;
}
bool get_network_list(network_info_list_t *out) {
    memset(out, 0, sizeof(*out));
    io_service_t s = service(); if (!s) return false;
    CFTypeRef v = property(s, CFSTR("wifi-networks"));
    if (v && CFGetTypeID(v) == CFArrayGetTypeID()) {
        CFArrayRef a = (CFArrayRef)v;
        for (CFIndex i = 0; i < CFArrayGetCount(a) && out->count < MAX_NETWORK_LIST_LENGTH; ++i) {
            struct ioctl_network_info candidate;
            if (mt7902_decode_network((CFDictionaryRef)CFArrayGetValueAtIndex(a, i), &candidate))
                out->networks[out->count++] = candidate;
        }
    }
    if (v) CFRelease(v);
    bool canScan = bool_property(s, CFSTR("scan-supported"));
    char state[32]; string_property(s, CFSTR("wifi-state"), state, sizeof(state)); IOObjectRelease(s);
    // Stage 2 stays in scan-ready, and a failed stage-3 join stays failed.
    // Both can rescan. The worker throttles requests; keep delivering its cache on Busy.
    if (mt7902_should_refresh_scan(enabled(), canScan, state)) command(0, NULL, 0);
    return true;
}
kern_return_t associate_ssid(const char *ssid, const char *password) {
    if (!enabled()) return kIOReturnNotReady;
    struct mt7902_join j;
    if (!mt7902_encode_join(&j, ssid, password)) return kIOReturnBadArgument;
    kern_return_t r = command(1, &j, sizeof(j)); memset_s(&j, sizeof(j), 0, sizeof(j)); return r;
}
kern_return_t join_ssid(const char *ssid, const char *password) { return associate_ssid(ssid, password); }
kern_return_t dis_associate_ssid(const char *ssid) { (void)ssid; return command(2, NULL, 0); }
bool connect_network(const char *ssid, const char *password) {
    if (associate_ssid(ssid, password) != KERN_SUCCESS) return false;
    for (unsigned i = 0; i < 90; ++i) {
        sleep(1);
        if (!enabled()) return false;
        uint32_t state;
        if (get_80211_state(&state) && state == ITL80211_S_RUN) {
            station_info_t st;
            if (!get_station_info(&st) && !strncmp(ssid, (const char *)st.ssid, 32)) return true;
        }
        io_service_t s = service(); if (!s) return false;
        char text[32]; string_property(s, CFSTR("wifi-state"), text, sizeof(text)); IOObjectRelease(s);
        if (!strcmp(text, "failed")) return false;
    }
    return false;
}
kern_return_t ioctl_get(int ctl, void *data, size_t size) {
    if (!data) return kIOReturnBadArgument;
    switch (ctl) {
    case IOCTL_80211_DRIVER_INFO: {
        if (size != sizeof(struct ioctl_driver_info)) return kIOReturnBadArgument;
        struct ioctl_driver_info *d = data; memset(d, 0, sizeof(*d)); d->version = IOCTL_VERSION;
        io_service_t s = service(); if (!s) return kIOReturnNotFound;
        string_property(s, CFSTR("port-version"), d->driver_version, sizeof(d->driver_version));
        strlcpy(d->fw_version, "MT7902 embedded firmware", sizeof(d->fw_version));
        CFTypeRef bsd = IORegistryEntrySearchCFProperty(s, kIOServicePlane, CFSTR("BSD Name"), kCFAllocatorDefault, kIORegistryIterateRecursively);
        mt7902_string(bsd, d->bsd_name, sizeof(d->bsd_name)); if (bsd) CFRelease(bsd);
        IOObjectRelease(s); return KERN_SUCCESS;
    }
    case IOCTL_80211_STA_INFO:
        return size == sizeof(station_info_t) ? get_station_info(data) : kIOReturnBadArgument;
    case IOCTL_80211_STATE: {
        if (size != sizeof(struct ioctl_state)) return kIOReturnBadArgument;
        struct ioctl_state *d = data; memset(d, 0, sizeof(*d)); d->version = IOCTL_VERSION; uint32_t state;
        if (!get_80211_state(&state)) return kIOReturnNotFound; d->state = (int)state; return KERN_SUCCESS;
    }
    case IOCTL_80211_POWER: {
        if (size != sizeof(struct ioctl_power)) return kIOReturnBadArgument;
        struct ioctl_power *d = data; memset(d, 0, sizeof(*d)); d->version = IOCTL_VERSION; bool on;
        if (!get_power_state(&on)) return kIOReturnNotFound; d->enabled = on; return KERN_SUCCESS;
    }
    default: return kIOReturnUnsupported;
    }
}
kern_return_t ioctl_set(int ctl, void *data, size_t size) {
    if (ctl == IOCTL_80211_SCAN && !size) return command(0, NULL, 0);
    (void)data; return kIOReturnUnsupported;
}
kern_return_t _ioctl(int ctl, bool get, void *data, size_t size) { return get ? ioctl_get(ctl, data, size) : ioctl_set(ctl, data, size); }
kern_return_t _nake_ioctl(io_connect_t c, int *ctl, bool get, void *data, size_t size) {
    (void)c; return _ioctl(*ctl, get, data, size);
}
void api_terminate(void) {} // no persistent kernel connection or heap-allocated synchronization objects
