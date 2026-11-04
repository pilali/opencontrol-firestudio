#include "fsfw.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/firewire/IOFireWireLib.h>
#include <libkern/OSByteOrder.h>
#include <pthread.h>

static IOFireWireLibDeviceRef gDev = NULL;
static io_service_t gSvc = 0;
static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;

int fs_is_open(void) { return gDev != NULL; }

void fs_close(void) {
    pthread_mutex_lock(&gLock);
    if (gDev) { (*gDev)->Close(gDev); (*gDev)->Release(gDev); gDev = NULL; }
    if (gSvc) { IOObjectRelease(gSvc); gSvc = 0; }
    pthread_mutex_unlock(&gLock);
}

int fs_open(void) {
    fs_close();
    CFMutableDictionaryRef m = IOServiceMatching("IOFireWireDevice");
    int vendor = 0xA92, model = 8;
    CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &vendor);
    CFNumberRef mo = CFNumberCreate(NULL, kCFNumberIntType, &model);
    CFDictionarySetValue(m, CFSTR("Vendor_ID"), v);
    CFDictionarySetValue(m, CFSTR("Model_ID"), mo);
    CFRelease(v); CFRelease(mo);
    io_service_t svc = IOServiceGetMatchingService(kIOMasterPortDefault, m);
    if (!svc) return -1;
    IOCFPlugInInterface **plug = NULL; SInt32 score;
    if (IOCreatePlugInInterfaceForService(svc, kIOFireWireLibTypeID, kIOCFPlugInInterfaceID, &plug, &score) || !plug) {
        IOObjectRelease(svc); return -2;
    }
    IOFireWireLibDeviceRef dev = NULL;
    (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOFireWireDeviceInterfaceID), (LPVOID *)&dev);
    IODestroyPlugInInterface(plug);
    if (!dev) { IOObjectRelease(svc); return -3; }
    if ((*dev)->Open(dev) != kIOReturnSuccess) { (*dev)->Release(dev); IOObjectRelease(svc); return -4; }
    pthread_mutex_lock(&gLock); gDev = dev; gSvc = svc; pthread_mutex_unlock(&gLock);
    return 0;
}

static int rq(uint32_t lo, uint32_t *out) {
    FWAddress a = { 0, 0xFFFF, lo }; UInt32 q = 0;
    IOReturn r = (*gDev)->ReadQuadlet(gDev, gSvc, &a, &q, false, 0);
    if (r) return r; *out = OSSwapBigToHostInt32(q); return 0;
}

int fs_read_abs(uint32_t addrLo, uint32_t *out) {
    pthread_mutex_lock(&gLock);
    int r = gDev ? rq(addrLo, out) : -1;
    pthread_mutex_unlock(&gLock);
    return r;
}

int fs_read(uint32_t offset, uint32_t *out, uint32_t count) {
    if ((offset & 3) || offset + count * 4 > FS_MIXER_SIZE) return -10;
    pthread_mutex_lock(&gLock);
    int r = gDev ? 0 : -1;
    uint32_t done = 0;
    while (!r && done < count) {
        uint32_t n = count - done; if (n > 16) n = 16;          /* blocs de 64 octets : les plus gros sont refusés */
        UInt32 buf[64]; UInt32 size = n * 4;
        FWAddress a = { 0, 0xFFFF, FS_MIXER_BASE + offset + done * 4 };
        IOReturn e = (*gDev)->Read(gDev, gSvc, &a, buf, &size, false, 0);
        if (e || size != n * 4) {                                /* repli : quadlet par quadlet */
            for (uint32_t i = 0; i < n && !r; i++) r = rq(FS_MIXER_BASE + offset + (done + i) * 4, &out[done + i]);
        } else {
            for (uint32_t i = 0; i < n; i++) out[done + i] = OSSwapBigToHostInt32(buf[i]);
        }
        done += n;
    }
    pthread_mutex_unlock(&gLock);
    return r;
}

int fs_write(uint32_t offset, uint32_t value) {
    /* Jamais au-delà des paramètres (en-tête, noms et vu-mètres exclus). */
    if ((offset & 3) || offset < 0x38 || offset >= 0x1168) return -10;
    pthread_mutex_lock(&gLock);
    int r = -1;
    if (gDev) {
        FWAddress a = { 0, 0xFFFF, FS_MIXER_BASE + offset };
        r = (*gDev)->WriteQuadlet(gDev, gSvc, &a, OSSwapHostToBigInt32(value), false, 0);
    }
    pthread_mutex_unlock(&gLock);
    return r;
}
