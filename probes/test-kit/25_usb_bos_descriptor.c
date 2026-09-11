/*
 * 25_usb_bos_descriptor.c - Read BOS (Binary Object Store) descriptors from
 * IOUSBHostDevice services. Cables with USB4 routers or Billboard devices
 * expose capability descriptors in userland without entitlements.
 *
 * Two stages:
 *   1. Dump IOKit-published properties whose keys look BOS/Billboard/USB4-ish.
 *   2. Fetch the raw BOS capability bytes via the legacy IOUSBDeviceInterface
 *      (IOCFPlugIn) using a USB control transfer GET_DESCRIPTOR(BOS). Parses
 *      common device capability descriptors: USB 2.0 Extension, SuperSpeed,
 *      SuperSpeedPlus, Container ID, Platform, Billboard, Configuration
 *      Summary, etc.
 *
 * This probe never calls USBDeviceOpen: the control transfer goes through
 * DeviceRequest on the unopened device interface, the same no-open pattern
 * used by Sources/WhatCableDarwinBackend/Watchers/BillboardDescriptorReader.swift.
 * That works without DriverKit / USB entitlements as long as no kernel driver
 * has exclusive-claimed the device, and it avoids the side effects of an
 * open (e.g. disturbing a mass-storage device's mounted volume).
 *
 * Compile:
 *   clang -framework IOKit -framework CoreFoundation \
 *     -o 25_usb_bos_descriptor 25_usb_bos_descriptor.c
 */

#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach.h>

#ifndef kUSBBOSDescriptor
#define kUSBBOSDescriptor 0x0F
#endif

static void printCFType(CFTypeRef value, int indent) {
    char pad[64] = {0};
    for (int i = 0; i < indent && i < 60; i++) pad[i] = ' ';

    if (!value) { printf("%s(null)\n", pad); return; }

    CFTypeID tid = CFGetTypeID(value);
    if (tid == CFStringGetTypeID()) {
        char buf[512];
        buf[0] = '\0';
        if (!CFStringGetCString(value, buf, sizeof(buf), kCFStringEncodingUTF8))
            snprintf(buf, sizeof(buf), "<unconvertible>");
        printf("%s%s\n", pad, buf);
    } else if (tid == CFNumberGetTypeID()) {
        long long num = 0;
        CFNumberGetValue(value, kCFNumberLongLongType, &num);
        printf("%s%lld (0x%llx)\n", pad, num, num);
    } else if (tid == CFDataGetTypeID()) {
        CFIndex len = CFDataGetLength(value);
        const UInt8 *bytes = CFDataGetBytePtr(value);
        printf("%sData[%ld]: ", pad, (long)len);
        for (CFIndex i = 0; i < len && i < 64; i++)
            printf("%02x ", bytes[i]);
        if (len > 64) printf("...");
        printf("\n");
    } else if (tid == CFBooleanGetTypeID()) {
        printf("%s%s\n", pad, CFBooleanGetValue(value) ? "true" : "false");
    } else if (tid == CFDictionaryGetTypeID()) {
        CFIndex count = CFDictionaryGetCount(value);
        printf("%sDict[%ld]:\n", pad, (long)count);
        CFIndex n = CFDictionaryGetCount(value);
        const void **keys = malloc(n * sizeof(void*));
        const void **vals = malloc(n * sizeof(void*));
        CFDictionaryGetKeysAndValues(value, keys, vals);
        for (CFIndex i = 0; i < n; i++) {
            char kbuf[256];
            kbuf[0] = '\0';
            if (!CFStringGetCString(keys[i], kbuf, sizeof(kbuf), kCFStringEncodingUTF8))
                snprintf(kbuf, sizeof(kbuf), "<unconvertible>");
            printf("%s  %s = ", pad, kbuf);
            printCFType(vals[i], indent + 4);
        }
        free(keys); free(vals);
    } else if (tid == CFArrayGetTypeID()) {
        CFIndex count = CFArrayGetCount(value);
        printf("%sArray[%ld]:\n", pad, (long)count);
        for (CFIndex i = 0; i < count; i++) {
            printf("%s  [%ld] ", pad, (long)i);
            printCFType(CFArrayGetValueAtIndex(value, i), indent + 4);
        }
    } else {
        printf("%s<unknown CF type %lu>\n", pad, (unsigned long)tid);
    }
}

static const char *capabilityName(UInt8 capType) {
    switch (capType) {
        case 0x01: return "Wireless USB";
        case 0x02: return "USB 2.0 Extension";
        case 0x03: return "SuperSpeed USB";
        case 0x04: return "Container ID";
        case 0x05: return "Platform";
        case 0x06: return "Power Delivery";
        case 0x07: return "Battery Info";
        case 0x08: return "PD Consumer Port";
        case 0x09: return "PD Provider Port";
        case 0x0a: return "SuperSpeedPlus";
        case 0x0b: return "Precision Time Measurement";
        case 0x0c: return "Wireless USB Ext";
        case 0x0d: return "Billboard";
        case 0x0e: return "Authentication";
        case 0x0f: return "Billboard Alternate Mode";
        case 0x10: return "Configuration Summary";
        case 0x11: return "FWStatus";
        default:   return "unknown";
    }
}

static void hexDump(const UInt8 *buf, int len, const char *pad) {
    for (int i = 0; i < len; i++) {
        if ((i % 16) == 0) printf("%s", pad);
        printf("%02x ", buf[i]);
        if ((i % 16) == 15) printf("\n");
    }
    if (len % 16) printf("\n");
}

static void parseSuperSpeed(const UInt8 *cap, UInt8 len) {
    if (len < 10) { printf("    (SS cap too short)\n"); return; }
    UInt16 speeds = cap[4] | (cap[5] << 8);
    UInt8 fnSupport = cap[6];
    UInt8 u1Exit = cap[7];
    UInt16 u2Exit = cap[8] | (cap[9] << 8);
    printf("    SpeedsSupported=0x%04x", speeds);
    if (speeds & (1 << 0)) printf(" LowSpeed");
    if (speeds & (1 << 1)) printf(" FullSpeed");
    if (speeds & (1 << 2)) printf(" HighSpeed");
    if (speeds & (1 << 3)) printf(" SuperSpeed");
    printf("\n");
    printf("    LowestFunctionalSpeed=%u U1DevExitLatency=%uus U2DevExitLatency=%uus\n",
           fnSupport, u1Exit, u2Exit);
}

static void parseSuperSpeedPlus(const UInt8 *cap, UInt8 len) {
    if (len < 12) { printf("    (SSPlus cap too short)\n"); return; }
    UInt32 attribs = cap[4] | (cap[5] << 8) | (cap[6] << 16) | (cap[7] << 24);
    UInt16 functional = cap[8] | (cap[9] << 8);
    UInt8 ssac = attribs & 0x1F;
    UInt8 ssic = (attribs >> 5) & 0x0F;
    UInt8 minRxLanes = functional & 0x0F;
    UInt8 minTxLanes = (functional >> 4) & 0x0F;
    printf("    SublinkSpeedAttribCount=%u (+1 entries) SublinkSpeedIDCount=%u\n",
           ssac, ssic);
    printf("    MinRxLanes=%u MinTxLanes=%u\n", minRxLanes, minTxLanes);
    int entries = ssac + 1;
    static const char *units[] = {"bps", "Kbps", "Mbps", "Gbps"};
    for (int s = 0; s < entries; s++) {
        int off = 12 + s * 4;
        if (off + 4 > len) break;
        UInt32 sl = cap[off] | (cap[off+1] << 8) | (cap[off+2] << 16) | (cap[off+3] << 24);
        UInt8 sid = sl & 0x0F;
        UInt8 lse = (sl >> 4) & 0x03;
        UInt8 st  = (sl >> 6) & 0x03;
        UInt8 dir = (sl >> 7) & 0x01;
        UInt8 prot = (sl >> 14) & 0x03;
        UInt16 mant = (sl >> 16) & 0xFFFF;
        printf("    SL[%d]: ID=%u dir=%c protocol=%s mantissa=%u exp=%s lane-count-encoded=%u\n",
               s, sid,
               dir ? 'T' : 'R',
               (prot == 0) ? "SuperSpeed" : (prot == 1) ? "SuperSpeedPlus" : "reserved",
               mant,
               units[lse],
               st);
    }
}

static void parseContainerID(const UInt8 *cap, UInt8 len) {
    if (len < 20) { printf("    (Container ID cap too short)\n"); return; }
    printf("    UUID: ");
    for (int i = 4; i < 20; i++) {
        printf("%02x", cap[i]);
        if (i == 7 || i == 9 || i == 11 || i == 13) printf("-");
    }
    printf("\n");
}

static void parseBillboard(const UInt8 *cap, UInt8 len) {
    /* Need 11 bytes: nAltModes@4, iAddlInfo@5, preferred@6, vconnPower@7..10. */
    if (len < 11) { printf("    (Billboard cap too short)\n"); return; }
    UInt8 nAltModes = cap[4];
    UInt8 iAddlInfo = cap[5];
    UInt8 preferred = cap[6];
    UInt32 vconnPower = cap[7] | (cap[8] << 8) | (cap[9] << 16) | (cap[10] << 24);
    printf("    NumberOfAlternateModes=%u iAddlInfoURL=%u PreferredAltMode=%u VconnPower=0x%08x\n",
           nAltModes, iAddlInfo, preferred, vconnPower);
}

static void parseUSB4(const UInt8 *cap, UInt8 len) {
    /* Need 7 bytes: bmAttributes@4, bcdUSBVersion at @5..@6 (little-endian). */
    if (len < 7) { printf("    (USB4 cap too short)\n"); return; }
    printf("    bmAttributes=0x%02x bcdUSBVersion=0x%02x%02x\n",
           cap[4], cap[6], cap[5]);
}

/* Read a small integer IOKit property as a long. Returns 1 on success. */
static int readIntProperty(io_service_t svc, const char *key, long *out) {
    CFStringRef cfKey = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    if (!cfKey) return 0;
    CFTypeRef val = IORegistryEntryCreateCFProperty(svc, cfKey, kCFAllocatorDefault, 0);
    CFRelease(cfKey);
    if (!val) return 0;
    int ok = 0;
    if (CFGetTypeID(val) == CFNumberGetTypeID()) {
        long n = 0;
        if (CFNumberGetValue(val, kCFNumberLongType, &n)) { *out = n; ok = 1; }
    }
    CFRelease(val);
    return ok;
}

/*
 * True if this USB device is (or contains) a Mass Storage interface
 * (USB class 0x08). We avoid opening these: opening a storage device whose
 * media is mounted as a removable volume makes macOS (Ventura+) raise the
 * "would like to access files on a removable volume" privacy prompt. We skip
 * every storage device rather than try to tell mounted from unmounted: it is
 * the conservative choice and the BOS descriptor of a flash drive or external
 * SSD is of no interest to the test kit, so skipping the open loses nothing
 * and spares the user a popup.
 *
 * Storage class can sit at the device level (bDeviceClass) or, more
 * commonly, on a child interface (bInterfaceClass) when the device reports
 * class 0x00 ("see interface"). Check both.
 *
 * Walk only the device's own (direct-child) interfaces; do NOT recurse the
 * subtree. In the IOService plane a hub's subtree contains the devices
 * plugged into it, so a recursive walk would flag a plain hub as "storage"
 * the moment a flash drive is attached downstream and skip the hub's own
 * BOS. A USB interface (IOUSBHostInterface, which carries bInterfaceClass)
 * is always a direct child of its IOUSBHostDevice, so one level is both
 * sufficient and correct here.
 */
static int deviceHasMassStorageInterface(io_service_t device) {
    enum { kUSBMassStorageClass = 0x08 };

    long deviceClass = 0;
    if (readIntProperty(device, "bDeviceClass", &deviceClass) &&
        deviceClass == kUSBMassStorageClass) {
        return 1;
    }

    io_iterator_t children = 0;
    if (IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) != KERN_SUCCESS) {
        return 0;
    }
    int found = 0;
    int sawAny = 0;
    io_service_t child;
    while ((child = IOIteratorNext(children)) != 0) {
        sawAny = 1;
        long interfaceClass = 0;
        if (readIntProperty(child, "bInterfaceClass", &interfaceClass) &&
            interfaceClass == kUSBMassStorageClass) {
            found = 1;
        }
        IOObjectRelease(child);
        if (found) break;
    }
    if (sawAny && !IOIteratorIsValid(children))
        printf("--- TRUNCATED: iterator invalidated mid-walk (registry changed) ---\n");
    IOObjectRelease(children);
    return found;
}

static void fetchBOSDescriptor(io_service_t service) {
    if (deviceHasMassStorageInterface(service)) {
        printf("  [BOS] Mass-storage device; skipping open to avoid the macOS "
               "removable-volume prompt (storage BOS not needed)\n");
        return;
    }

    IOCFPlugInInterface **plugIn = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(service,
        kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
        &plugIn, &score);
    if (kr != KERN_SUCCESS || !plugIn) {
        printf("  [BOS] IOCreatePlugInInterfaceForService failed: 0x%x\n", kr);
        return;
    }

    IOUSBDeviceInterface **dev = NULL;
    HRESULT hr = (*plugIn)->QueryInterface(plugIn,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
        (LPVOID *)&dev);
    IODestroyPlugInInterface(plugIn);
    if (hr || !dev) {
        printf("  [BOS] QueryInterface(IOUSBDeviceInterface) failed: 0x%lx\n", (long)hr);
        return;
    }

    /* Stage A: fetch BOS descriptor header (5 bytes) to learn wTotalLength. */
    UInt8 header[5] = {0};
    IOUSBDevRequest req;
    memset(&req, 0, sizeof(req));
    req.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBStandard, kUSBDevice);
    req.bRequest      = kUSBRqGetDescriptor;
    req.wValue        = (kUSBBOSDescriptor << 8) | 0;
    req.wIndex        = 0;
    req.wLength       = sizeof(header);
    req.pData         = header;

    kr = (*dev)->DeviceRequest(dev, &req);
    if (kr != kIOReturnSuccess) {
        printf("  [BOS] GET_DESCRIPTOR(BOS, 5) failed: 0x%x\n", kr);
        goto done;
    }
    if (header[1] != 0x0F) {
        printf("  [BOS] Header bDescriptorType=0x%02x, expected 0x0F. Device has no BOS.\n",
               header[1]);
        goto done;
    }

    UInt16 total = header[2] | (header[3] << 8);
    UInt8 numCaps = header[4];
    printf("  [BOS] Header OK: wTotalLength=%u bNumDeviceCaps=%u\n", total, numCaps);

    if (total < 5 || total > 4096) {
        printf("  [BOS] wTotalLength=%u outside sane range; aborting\n", total);
        goto done;
    }

    /* Stage B: fetch the full BOS descriptor. */
    UInt8 *buf = calloc(1, total);
    if (!buf) goto done;
    req.wLength = total;
    req.pData   = buf;
    kr = (*dev)->DeviceRequest(dev, &req);
    if (kr != kIOReturnSuccess) {
        printf("  [BOS] GET_DESCRIPTOR(BOS, %u) failed: 0x%x\n", total, kr);
        free(buf);
        goto done;
    }
    printf("  [BOS] Full descriptor bytes (%u):\n", total);
    hexDump(buf, total, "    ");

    /* Walk capability descriptors. */
    int offset = 5;
    int idx = 0;
    while (offset + 3 <= total) {
        UInt8 capLen  = buf[offset];
        UInt8 dtype   = buf[offset + 1];
        UInt8 capType = buf[offset + 2];
        if (capLen < 3 || offset + capLen > total) {
            printf("  [BOS cap %d] truncated (len=%u at offset=%d)\n", idx, capLen, offset);
            break;
        }
        if (dtype != 0x10) {
            printf("  [BOS cap %d] unexpected bDescriptorType=0x%02x; skipping\n", idx, dtype);
            offset += capLen;
            idx++;
            continue;
        }
        printf("  [BOS cap %d] type=0x%02x (%s) len=%u\n",
               idx, capType, capabilityName(capType), capLen);
        const UInt8 *cap = buf + offset;
        switch (capType) {
            case 0x03: parseSuperSpeed(cap, capLen); break;
            case 0x0a: parseSuperSpeedPlus(cap, capLen); break;
            case 0x04: parseContainerID(cap, capLen); break;
            case 0x0d: parseBillboard(cap, capLen); break;
            case 0x11: parseUSB4(cap, capLen); break;
            default:
                if (capLen > 3) {
                    printf("    payload: ");
                    for (int i = 3; i < capLen; i++) printf("%02x ", cap[i]);
                    printf("\n");
                }
                break;
        }
        offset += capLen;
        idx++;
    }

    free(buf);

done:
    (*dev)->Release(dev);
}

static void dumpServiceProperties(io_service_t service, const char *label) {
    CFMutableDictionaryRef props = NULL;
    kern_return_t kr = IORegistryEntryCreateCFProperties(service, &props,
        kCFAllocatorDefault, 0);
    if (kr != KERN_SUCCESS || !props) return;

    printf("\n--- %s ---\n", label);

    // Key properties for BOS/Billboard
    const char *interesting[] = {
        "USB Product Name", "USB Vendor Name", "idVendor", "idProduct",
        "bcdUSB", "bDeviceClass", "bDeviceSubClass", "bDeviceProtocol",
        "USB Speed", "UsbDeviceSpeed", "PortNum",
        "BOSDescriptor", "BOS Descriptor", "bos-descriptor",
        "BillboardCapability", "Billboard", "billboard",
        "USB4Version", "USB4", "usb4-capabilities",
        "SuperSpeed", "SuperSpeedPlus", "SSPCapability",
        "bNumConfigurations", "locationID", "sessionID",
        "kUSBContainerID", "ContainerID",
        /* Device serial: the only thing that separates two IDENTICAL devices
         * (same VID/PID) on one machine, and a join key shared with probes
         * 04/17/19/38. It identifies a peripheral, not a person. Keep it. */
        "USB Serial Number", "iSerialNumber",
        NULL
    };

    for (int i = 0; interesting[i]; i++) {
        CFStringRef key = CFStringCreateWithCString(NULL, interesting[i], kCFStringEncodingUTF8);
        CFTypeRef val = CFDictionaryGetValue(props, key);
        if (val) {
            printf("  %s = ", interesting[i]);
            printCFType(val, 4);
        }
        CFRelease(key);
    }

    // Also check for any key containing "BOS", "Billboard", "Capability", "USB4"
    CFIndex n = CFDictionaryGetCount(props);
    const void **keys = malloc(n * sizeof(void*));
    const void **vals = malloc(n * sizeof(void*));
    CFDictionaryGetKeysAndValues(props, keys, vals);
    for (CFIndex i = 0; i < n; i++) {
        char kbuf[256];
        kbuf[0] = '\0';
        if (!CFStringGetCString(keys[i], kbuf, sizeof(kbuf), kCFStringEncodingUTF8))
            snprintf(kbuf, sizeof(kbuf), "<unconvertible>");
        if (strcasestr(kbuf, "BOS") || strcasestr(kbuf, "Billboard") ||
            strcasestr(kbuf, "USB4") || strcasestr(kbuf, "Capability") ||
            strcasestr(kbuf, "Descriptor") || strcasestr(kbuf, "Speed") ||
            strcasestr(kbuf, "Generation") || strcasestr(kbuf, "Lane") ||
            strcasestr(kbuf, "Tunnel")) {
            printf("  [MATCH] %s = ", kbuf);
            printCFType(vals[i], 4);
        }
    }
    free(keys); free(vals);

    // Stage 2: actually fetch the BOS descriptor via control transfer.
    fetchBOSDescriptor(service);

    CFRelease(props);
}

int main(void) {
    printf("Running as uid=%d\n\n", getuid());

    // Find all IOUSBHostDevice services
    printf("=== IOUSBHostDevice services ===\n");
    io_iterator_t iter;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOUSBHostDevice"), &iter);

    if (kr == KERN_SUCCESS) {
        io_service_t svc;
        int count = 0;
        while ((svc = IOIteratorNext(iter)) != 0) {
            io_name_t name = {0};
            IORegistryEntryGetName(svc, name);
            char label[256];
            snprintf(label, sizeof(label), "IOUSBHostDevice[%d] \"%s\"", count, name);
            dumpServiceProperties(svc, label);
            IOObjectRelease(svc);
            count++;
        }
        if (count > 0 && !IOIteratorIsValid(iter))
            printf("--- TRUNCATED: iterator invalidated mid-walk (registry changed) ---\n");
        IOObjectRelease(iter);
        printf("\nTotal IOUSBHostDevice services: %d\n", count);
    }

    // Also look for AppleUSB4Hub / USB4 router services
    printf("\n=== USB4 Router/Hub services ===\n");
    const char *usb4Classes[] = {
        "AppleUSB4Hub", "IOThunderboltUSB4Router",
        "AppleUSB40DevicePort", "AppleUSB40HostPort",
        "IOUSBHostHubDevice", NULL
    };
    for (int c = 0; usb4Classes[c]; c++) {
        kr = IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching(usb4Classes[c]), &iter);
        if (kr == KERN_SUCCESS) {
            io_service_t svc;
            int count = 0;
            while ((svc = IOIteratorNext(iter)) != 0) {
                char label[256];
                snprintf(label, sizeof(label), "%s[%d]", usb4Classes[c], count);
                dumpServiceProperties(svc, label);
                IOObjectRelease(svc);
                count++;
            }
            if (count > 0 && !IOIteratorIsValid(iter))
                printf("--- TRUNCATED: iterator invalidated mid-walk (registry changed) ---\n");
            IOObjectRelease(iter);
            if (count > 0) printf("  Found %d %s\n", count, usb4Classes[c]);
        }
    }

    // Look for Billboard class. The class macOS instantiates on Apple Silicon
    // is "AppleUSBHostBillboardDevice"; the older "IOUSBHostBillboardDevice"
    // name matches nothing here, which is why earlier runs reported 0. We try
    // both so the probe works regardless of macOS naming. dumpServiceProperties
    // already prints bDeviceClass, the spec-defined Billboard class (0x11),
    // which we want to confirm against live hardware.
    printf("\n=== Billboard devices ===\n");
    const char *billboardClasses[] = {"AppleUSBHostBillboardDevice", "IOUSBHostBillboardDevice"};
    int billboardCount = 0;
    uint64_t seenIDs[64];
    int seenCount = 0;
    for (size_t bc = 0; bc < sizeof(billboardClasses) / sizeof(billboardClasses[0]); bc++) {
        kr = IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching(billboardClasses[bc]), &iter);
        if (kr != KERN_SUCCESS) continue;
        io_service_t svc;
        int sawAny = 0;
        while ((svc = IOIteratorNext(iter)) != 0) {
            sawAny = 1;
            // Class matching includes subclasses, so if AppleUSBHostBillboardDevice
            // is a subclass of IOUSBHostBillboardDevice the two iterators can return
            // the same service. Dedupe by registry entry ID before counting/dumping.
            uint64_t entryID = 0;
            IORegistryEntryGetRegistryEntryID(svc, &entryID);
            int alreadySeen = 0;
            for (int s = 0; s < seenCount; s++) {
                if (seenIDs[s] == entryID) { alreadySeen = 1; break; }
            }
            if (!alreadySeen) {
                if (seenCount < (int)(sizeof(seenIDs) / sizeof(seenIDs[0]))) {
                    seenIDs[seenCount++] = entryID;
                }
                char label[256];
                snprintf(label, sizeof(label), "Billboard[%d] (%s)", billboardCount, billboardClasses[bc]);
                dumpServiceProperties(svc, label);
                billboardCount++;
            }
            IOObjectRelease(svc);
        }
        if (sawAny && !IOIteratorIsValid(iter))
            printf("--- TRUNCATED: iterator invalidated mid-walk (registry changed) ---\n");
        IOObjectRelease(iter);
    }
    printf("  Found %d billboard devices\n", billboardCount);

    return 0;
}
