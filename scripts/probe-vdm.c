/*
 * probe-vdm.c - Test whether we can read VDM payload data from AppleHPMLib.
 *
 * Probes the IOAccessoryManagerUserClient on each USB-C port to check:
 *   1. Can we open the user client without special entitlements?
 *   2. Does selector 4 (receiveVDM) return any data?
 *   3. Does selector 1 (iecsRead) let us read VDM-related registers?
 *
 * Build:  clang -o probe-vdm scripts/probe-vdm.c -framework IOKit -framework CoreFoundation
 * Run:    ./probe-vdm          (try without root first)
 *         sudo ./probe-vdm    (try with root if the above fails)
 *
 * This is a throwaway research tool, not production code.
 */

#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

static const char *ioreturn_name(kern_return_t kr) {
    switch (kr) {
        case KERN_SUCCESS:           return "SUCCESS";
        case 0xe00002c2:             return "kIOReturnNotPermitted";
        case 0xe00002bc:             return "kIOReturnNotPrivileged";
        case 0xe00002c7:             return "kIOReturnExclusiveAccess";
        case 0xe00002be:             return "kIOReturnBadArgument";
        case 0xe00002ed:             return "kIOReturnUnsupported";
        case 0xe00002f0:             return "kIOReturnNotFound";
        case 0xe00002eb:             return "kIOReturnNoDevice";
        default:                     return "unknown";
    }
}

static void print_hex(const uint8_t *buf, size_t len) {
    for (size_t i = 0; i < len; i++) {
        printf("%02x", buf[i]);
        if ((i + 1) % 16 == 0) printf("\n    ");
        else if ((i + 1) % 4 == 0) printf(" ");
    }
    printf("\n");
}

static void probe_port(io_service_t service, const char *name) {
    printf("\n=== %s ===\n", name);

    io_connect_t connect = 0;
    kern_return_t kr;

    /* Try opening the user client */
    kr = IOServiceOpen(service, mach_task_self(), 0, &connect);
    printf("  IOServiceOpen(type=0): 0x%x (%s)\n", kr, ioreturn_name(kr));

    if (kr != KERN_SUCCESS) {
        /* Try type 1 in case that's the read-only client */
        kr = IOServiceOpen(service, mach_task_self(), 1, &connect);
        printf("  IOServiceOpen(type=1): 0x%x (%s)\n", kr, ioreturn_name(kr));
    }

    if (kr != KERN_SUCCESS) {
        printf("  Cannot open user client. Try with sudo.\n");
        return;
    }

    printf("  User client opened successfully (connect=%u)\n", connect);

    /*
     * Selector 4: receiveVDM
     * Signature: receiveVDM(void*, uint64_t, uint64_t, uint64_t, uint32_t,
     *                       AppleHPMSOPType*, uint8_t*, uint64_t*)
     * Try with various input scalar counts since we're guessing the ABI.
     */
    printf("\n  --- Selector 4 (receiveVDM) ---\n");
    {
        uint64_t input[4] = {0, 0, 0, 0};
        uint64_t output[8] = {0};
        uint32_t outputCount = 8;

        kr = IOConnectCallScalarMethod(connect, 4, input, 4, output, &outputCount);
        printf("  CallScalar(sel=4, in=4): 0x%x (%s), outCount=%u\n",
               kr, ioreturn_name(kr), outputCount);
        if (kr == KERN_SUCCESS && outputCount > 0) {
            printf("  Output scalars:");
            for (uint32_t i = 0; i < outputCount; i++)
                printf(" [%u]=0x%llx", i, output[i]);
            printf("\n");
        }

        /* Also try with struct output (the payload might come as struct data) */
        uint8_t structOut[256] = {0};
        size_t structOutSize = sizeof(structOut);
        uint64_t input2[4] = {0, 0, 0, 0};

        kr = IOConnectCallMethod(connect, 4,
                                 input2, 4,    /* scalar in */
                                 NULL, 0,      /* struct in */
                                 output, &outputCount, /* scalar out */
                                 structOut, &structOutSize); /* struct out */
        printf("  CallMethod(sel=4, structOut): 0x%x (%s), structSize=%zu\n",
               kr, ioreturn_name(kr), structOutSize);
        if (kr == KERN_SUCCESS && structOutSize > 0) {
            printf("  Struct output (%zu bytes):\n    ", structOutSize);
            print_hex(structOut, structOutSize > 64 ? 64 : structOutSize);
        }
    }

    /*
     * Selector 5: receiveVDMAttention
     * Same signature as receiveVDM but for attention VDMs.
     */
    printf("\n  --- Selector 5 (receiveVDMAttention) ---\n");
    {
        uint64_t input[4] = {0, 0, 0, 0};
        uint64_t output[8] = {0};
        uint32_t outputCount = 8;

        kr = IOConnectCallScalarMethod(connect, 5, input, 4, output, &outputCount);
        printf("  CallScalar(sel=5, in=4): 0x%x (%s), outCount=%u\n",
               kr, ioreturn_name(kr), outputCount);
        if (kr == KERN_SUCCESS && outputCount > 0) {
            printf("  Output scalars:");
            for (uint32_t i = 0; i < outputCount; i++)
                printf(" [%u]=0x%llx", i, output[i]);
            printf("\n");
        }
    }

    /*
     * Selector 1: iecsRead - try reading VDM-related registers.
     * TPS6598x register map (may not match Apple's custom chip):
     *   0x4d = macvdmtool response register
     *   0x60 = Rx User SVID Attention VDM
     *   0x61 = Rx User SVID Non-attention VDM
     *   0x1a = Status register
     *   0x5f = Data Status register
     */
    printf("\n  --- Selector 1 (iecsRead) ---\n");
    uint8_t regs[] = {0x1a, 0x3f, 0x4d, 0x5f, 0x60, 0x61};
    const char *regNames[] = {"Status", "PowerStatus", "VDM Response (macvdm)",
                               "DataStatus", "RxAttentionVDM", "RxNonAttnVDM"};

    for (int i = 0; i < 6; i++) {
        uint64_t input[5] = {regs[i], 0, 0, 0, 0};
        uint64_t output[8] = {0};
        uint32_t outputCount = 8;

        kr = IOConnectCallScalarMethod(connect, 1, input, 5, output, &outputCount);
        printf("  Reg 0x%02x (%s): 0x%x (%s)",
               regs[i], regNames[i], kr, ioreturn_name(kr));
        if (kr == KERN_SUCCESS && outputCount > 0) {
            printf(" =");
            for (uint32_t j = 0; j < outputCount; j++)
                printf(" 0x%llx", output[j]);
        }
        printf("\n");

        /* Also try with struct output for larger register reads */
        uint8_t structOut[128] = {0};
        size_t structOutSize = sizeof(structOut);

        kr = IOConnectCallMethod(connect, 1,
                                 input, 5, NULL, 0,
                                 output, &outputCount,
                                 structOut, &structOutSize);
        if (kr == KERN_SUCCESS && structOutSize > 0) {
            printf("    Struct data (%zu bytes): ", structOutSize);
            print_hex(structOut, structOutSize > 32 ? 32 : structOutSize);
        }
    }

    /*
     * Bonus: try selectors 0 through 13 with no inputs to map the interface.
     * Only report the return code, don't try to write/send anything.
     */
    printf("\n  --- Selector survey (read-only probe) ---\n");
    for (int sel = 0; sel <= 13; sel++) {
        if (sel == 0) continue;  /* skip sendVDM */
        if (sel == 3) continue;  /* skip iecsWrite */
        if (sel == 7) continue;  /* skip forceMode */
        if (sel == 8) continue;  /* skip forceUpdateMode */

        uint64_t output[4] = {0};
        uint32_t outputCount = 4;

        kr = IOConnectCallScalarMethod(connect, sel, NULL, 0, output, &outputCount);
        printf("  Selector %2d: 0x%x (%s), outCount=%u\n",
               sel, kr, ioreturn_name(kr), outputCount);
    }

    IOServiceClose(connect);
}

int main(void) {
    printf("probe-vdm: Testing VDM payload access via IOAccessoryManagerUserClient\n");
    printf("Running as uid=%d\n\n", getuid());

    io_iterator_t iter;
    kern_return_t kr;

    /* Match AppleHPMInterfaceType10 (USB-C ports) */
    CFMutableDictionaryRef match = IOServiceMatching("AppleHPMInterfaceType10");
    kr = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter);
    if (kr != KERN_SUCCESS) {
        printf("No AppleHPMInterfaceType10 services found (0x%x)\n", kr);
        return 1;
    }

    io_service_t service;
    while ((service = IOIteratorNext(iter)) != 0) {
        CFStringRef desc = IORegistryEntryCreateCFProperty(
            service, CFSTR("Description"), kCFAllocatorDefault, 0);
        char name[128] = "unknown";
        if (desc) {
            CFStringGetCString(desc, name, sizeof(name), kCFStringEncodingUTF8);
            CFRelease(desc);
        }

        probe_port(service, name);
        IOObjectRelease(service);
    }

    IOObjectRelease(iter);
    printf("\nDone.\n");
    return 0;
}
