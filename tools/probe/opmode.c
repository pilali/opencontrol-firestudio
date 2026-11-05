// Prints, or sets, the operation mode of the PreSonus FireWire audio driver (PaeFireStudio.kext).
// See docs/driver-settings.md. Setting a mode restarts the audio stream; the PreSonus daemon saves it.
//   build/opmode       prints the current mode
//   build/opmode 0..3  sets the mode
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("PaeFireStudio"));
    if (!svc) { fprintf(stderr, "PreSonus driver (PaeFireStudio) not loaded\n"); return 1; }
    io_connect_t c;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &c);
    IOObjectRelease(svc);
    if (kr) { fprintf(stderr, "IOServiceOpen: 0x%x\n", kr); return 1; }

    uint32_t mode = 0; size_t sz = sizeof mode;
    kr = IOConnectCallStructMethod(c, 7, NULL, 0, &mode, &sz);           /* GetOpMode */
    if (kr) { fprintf(stderr, "GetOpMode: 0x%x\n", kr); IOServiceClose(c); return 1; }
    printf("operation mode: %u\n", mode);

    if (argc > 1) {
        char *end; unsigned long m = strtoul(argv[1], &end, 0);
        if (*end || m > 3) { fprintf(stderr, "mode must be 0-3\n"); IOServiceClose(c); return 2; }
        uint32_t v = (uint32_t)m;
        kr = IOConnectCallStructMethod(c, 8, &v, sizeof v, NULL, NULL);  /* SetOpMode */
        if (kr) { fprintf(stderr, "SetOpMode: 0x%x\n", kr); IOServiceClose(c); return 1; }
        sz = sizeof mode; IOConnectCallStructMethod(c, 7, NULL, 0, &mode, &sz);
        printf("operation mode now: %u\n", mode);
    }
    IOServiceClose(c);
    return 0;
}
