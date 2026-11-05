// Lists the FireStudio units seen on the FireWire bus and by the PreSonus driver (read only).
// See docs/driver-settings.md, "Several units on the bus".
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>

static uint64_t num(io_service_t s, CFStringRef key) {
    uint64_t v = 0;
    CFTypeRef p = IORegistryEntryCreateCFProperty(s, key, kCFAllocatorDefault, 0);
    if (p) { if (CFGetTypeID(p) == CFNumberGetTypeID()) CFNumberGetValue(p, kCFNumberSInt64Type, &v); CFRelease(p); }
    return v;
}

int main(void) {
    printf("FireWire bus (vendor 0xA92):\n");
    io_iterator_t it; io_service_t s;
    if (!IOServiceGetMatchingServices(0, IOServiceMatching("IOFireWireDevice"), &it)) {
        while ((s = IOIteratorNext(it))) {
            if (num(s, CFSTR("Vendor_ID")) == 0xA92)
                printf("  GUID %016llx  model 0x%llx%s\n", num(s, CFSTR("GUID")), num(s, CFSTR("Model_ID")),
                       num(s, CFSTR("Model_ID")) == 8 ? "  (FireStudio 26x26)" : "");
            IOObjectRelease(s);
        }
        IOObjectRelease(it);
    }

    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("PaeFireStudio"));
    if (!svc) { printf("PreSonus driver not loaded\n"); return 0; }
    io_connect_t c;
    if (IOServiceOpen(svc, mach_task_self(), 0, &c)) { printf("cannot open the driver\n"); return 1; }
    IOObjectRelease(svc);
    static uint8_t b[0xEE8]; size_t sz = sizeof b;
    if (IOConnectCallStructMethod(c, 3, NULL, 0, b, &sz)) { printf("GetConfigInfo failed\n"); return 1; }
    uint32_t *q = (uint32_t *)b;
    printf("PreSonus driver:\n  master GUID %016llx, clock source 0x%x, rate index %u\n",
           *(uint64_t *)b, q[3], q[4]);
    printf("  %u device(s), %u inputs, %u outputs in total\n",
           *(uint32_t *)(b + 0xED8), *(uint32_t *)(b + 0xEDC), *(uint32_t *)(b + 0xEE0));
    for (int i = 0; i < 5; i++) {
        uint8_t *e = b + 0xD20 + i * 0x58;
        if (*(uint64_t *)e == ~0ULL) continue;
        printf("  slot %u  GUID %016llx  \"%.63s\"  state %u\n",
               *(uint32_t *)(e + 0x4C), *(uint64_t *)e, (char *)(e + 8), *(uint32_t *)(e + 0x48));
    }
    IOServiceClose(c);
    return 0;
}
