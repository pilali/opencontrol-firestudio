#include "fsfw.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/firewire/IOFireWireLib.h>
#include <libkern/OSByteOrder.h>
#include <pthread.h>
#include <stdlib.h>

struct fs_unit {
    IOFireWireLibDeviceRef dev;
    io_service_t svc;
    uint64_t guid;
    pthread_mutex_t lock;
};

static CFMutableDictionaryRef matching(void) {
    CFMutableDictionaryRef m = IOServiceMatching("IOFireWireDevice");
    int vendor = 0xA92, model = 8;
    CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &vendor);
    CFNumberRef mo = CFNumberCreate(NULL, kCFNumberIntType, &model);
    CFDictionarySetValue(m, CFSTR("Vendor_ID"), v);
    CFDictionarySetValue(m, CFSTR("Model_ID"), mo);
    CFRelease(v); CFRelease(mo);
    return m;
}

static uint64_t service_guid(io_service_t svc) {
    uint64_t g = 0;
    CFTypeRef p = IORegistryEntryCreateCFProperty(svc, CFSTR("GUID"), kCFAllocatorDefault, 0);
    if (p) {
        if (CFGetTypeID(p) == CFNumberGetTypeID()) CFNumberGetValue(p, kCFNumberSInt64Type, &g);
        CFRelease(p);
    }
    return g;
}

int fs_list(uint64_t *guids, int max) {
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching(), &it)) return 0;
    int n = 0;
    io_service_t s;
    while ((s = IOIteratorNext(it))) {
        if (n < max) guids[n] = service_guid(s);
        n++;
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    return n;
}

fs_unit *fs_open(uint64_t guid, int *err) {
    io_iterator_t it = 0;
    io_service_t svc = 0, s;
    *err = -1;
    if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching(), &it)) return NULL;
    while ((s = IOIteratorNext(it))) {
        if (!svc && (guid == 0 || service_guid(s) == guid)) svc = s; else IOObjectRelease(s);
    }
    IOObjectRelease(it);
    if (!svc) return NULL;

    IOCFPlugInInterface **plug = NULL; SInt32 score;
    if (IOCreatePlugInInterfaceForService(svc, kIOFireWireLibTypeID, kIOCFPlugInInterfaceID, &plug, &score) || !plug) {
        IOObjectRelease(svc); *err = -2; return NULL;
    }
    IOFireWireLibDeviceRef dev = NULL;
    (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOFireWireDeviceInterfaceID), (LPVOID *)&dev);
    IODestroyPlugInInterface(plug);
    if (!dev) { IOObjectRelease(svc); *err = -3; return NULL; }
    if ((*dev)->Open(dev) != kIOReturnSuccess) { (*dev)->Release(dev); IOObjectRelease(svc); *err = -4; return NULL; }

    fs_unit *u = calloc(1, sizeof *u);
    u->dev = dev; u->svc = svc; u->guid = service_guid(svc);
    pthread_mutex_init(&u->lock, NULL);
    *err = 0;
    return u;
}

void fs_close(fs_unit *u) {
    if (!u) return;
    pthread_mutex_lock(&u->lock);
    (*u->dev)->Close(u->dev); (*u->dev)->Release(u->dev);
    IOObjectRelease(u->svc);
    pthread_mutex_unlock(&u->lock);
    pthread_mutex_destroy(&u->lock);
    free(u);
}

uint64_t fs_guid(const fs_unit *u) { return u ? u->guid : 0; }

static int rq(fs_unit *u, uint32_t lo, uint32_t *out) {
    FWAddress a = { 0, 0xFFFF, lo }; UInt32 q = 0;
    IOReturn r = (*u->dev)->ReadQuadlet(u->dev, u->svc, &a, &q, false, 0);
    if (r) return r; *out = OSSwapBigToHostInt32(q); return 0;
}

int fs_read_abs(fs_unit *u, uint32_t addrLo, uint32_t *out) {
    if (!u) return -1;
    pthread_mutex_lock(&u->lock);
    int r = rq(u, addrLo, out);
    pthread_mutex_unlock(&u->lock);
    return r;
}

int fs_read(fs_unit *u, uint32_t offset, uint32_t *out, uint32_t count) {
    if (!u) return -1;
    if ((offset & 3) || offset + count * 4 > FS_MIXER_SIZE) return -10;
    pthread_mutex_lock(&u->lock);
    int r = 0;
    uint32_t done = 0;
    while (!r && done < count) {
        uint32_t n = count - done; if (n > 16) n = 16;          /* 64-byte blocks */
        UInt32 buf[64]; UInt32 size = n * 4;
        FWAddress a = { 0, 0xFFFF, FS_MIXER_BASE + offset + done * 4 };
        IOReturn e = (*u->dev)->Read(u->dev, u->svc, &a, buf, &size, false, 0);
        if (e || size != n * 4) {                                /* fallback: quadlet by quadlet */
            for (uint32_t i = 0; i < n && !r; i++) r = rq(u, FS_MIXER_BASE + offset + (done + i) * 4, &out[done + i]);
        } else {
            for (uint32_t i = 0; i < n; i++) out[done + i] = OSSwapBigToHostInt32(buf[i]);
        }
        done += n;
    }
    pthread_mutex_unlock(&u->lock);
    return r;
}

int fs_write(fs_unit *u, uint32_t offset, uint32_t value) {
    if (!u) return -1;
    /* Never beyond the parameters (header, names and meters are protected). */
    if ((offset & 3) || offset < 0x38 || offset >= 0x1168) return -10;
    pthread_mutex_lock(&u->lock);
    FWAddress a = { 0, 0xFFFF, FS_MIXER_BASE + offset };
    int r = (*u->dev)->WriteQuadlet(u->dev, u->svc, &a, OSSwapHostToBigInt32(value), false, 0);
    pthread_mutex_unlock(&u->lock);
    return r;
}
