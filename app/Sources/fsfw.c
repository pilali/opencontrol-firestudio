#include "fsfw.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/firewire/IOFireWireLib.h>
#include <libkern/OSByteOrder.h>
#include <pthread.h>
#include <stdlib.h>

/* Access path: the units are never opened. Opening an IOFireWireDevice from user space makes IOFireWireFamily
   suspend, then resume, the PreSonus driver attached to it (kIOMessageServiceIsSuspended / IsResumed), which
   restarts the audio streams: an audible gap. Instead, transactions go through the Mac's own node
   (IOFireWireLocalNode), addressed to the unit's current node ID and bus generation. */
struct fs_unit {
    IOFireWireLibDeviceRef dev;     /* never opened: only used to get the node ID and bus generation */
    io_service_t svc;
    uint64_t guid;
    pthread_mutex_t lock;
    struct fs_unit *next;           /* list of open units, for the cleanup at exit */
};

static pthread_mutex_t local_lock = PTHREAD_MUTEX_INITIALIZER;
static IOFireWireLibDeviceRef local = NULL;
static int local_users = 0;
static fs_unit *units = NULL;

static IOFireWireLibDeviceRef interface_for(io_service_t svc) {
    IOCFPlugInInterface **plug = NULL; SInt32 score;
    if (IOCreatePlugInInterfaceForService(svc, kIOFireWireLibTypeID, kIOCFPlugInInterfaceID, &plug, &score) || !plug)
        return NULL;
    IOFireWireLibDeviceRef dev = NULL;
    (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOFireWireDeviceInterfaceID), (LPVOID *)&dev);
    IODestroyPlugInInterface(plug);
    return dev;
}

/* A process that exits with FireWire user clients still alive (the local node, or a unit's interface) makes the
   kernel clean them up, which resets the FireWire bus two or three times: the PreSonus driver restarts the audio
   streams after each reset. Everything is therefore released before the process exits. */
static void local_close_at_exit(void) {
    if (pthread_mutex_trylock(&local_lock) != 0) return;
    for (fs_unit *u = units; u; u = u->next) { (*u->dev)->Release(u->dev); u->dev = NULL; }
    units = NULL;
    if (local) { (*local)->Close(local); (*local)->Release(local); local = NULL; local_users = 0; }
    pthread_mutex_unlock(&local_lock);
}

static int local_retain(void) {
    static int registered = 0;
    pthread_mutex_lock(&local_lock);
    if (!registered) { atexit(local_close_at_exit); registered = 1; }
    if (!local) {
        io_service_t ln = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOFireWireLocalNode"));
        if (ln) {
            local = interface_for(ln);
            IOObjectRelease(ln);
            if (local && (*local)->Open(local) != kIOReturnSuccess) { (*local)->Release(local); local = NULL; }
        }
    }
    int ok = local != NULL;
    if (ok) local_users++;
    pthread_mutex_unlock(&local_lock);
    return ok;
}

static void local_release(void) {
    pthread_mutex_lock(&local_lock);
    if (local && --local_users == 0) { (*local)->Close(local); (*local)->Release(local); local = NULL; }
    pthread_mutex_unlock(&local_lock);
}

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

    IOFireWireLibDeviceRef dev = interface_for(svc);
    if (!dev) { IOObjectRelease(svc); *err = -2; return NULL; }
    if (!local_retain()) { (*dev)->Release(dev); IOObjectRelease(svc); *err = -3; return NULL; }

    fs_unit *u = calloc(1, sizeof *u);
    u->dev = dev; u->svc = svc; u->guid = service_guid(svc);
    pthread_mutex_init(&u->lock, NULL);
    pthread_mutex_lock(&local_lock);
    u->next = units; units = u;
    pthread_mutex_unlock(&local_lock);
    *err = 0;
    return u;
}

void fs_close(fs_unit *u) {
    if (!u) return;
    pthread_mutex_lock(&local_lock);
    for (fs_unit **p = &units; *p; p = &(*p)->next) if (*p == u) { *p = u->next; break; }
    pthread_mutex_unlock(&local_lock);
    pthread_mutex_lock(&u->lock);
    if (u->dev) (*u->dev)->Release(u->dev);
    IOObjectRelease(u->svc);
    pthread_mutex_unlock(&u->lock);
    pthread_mutex_destroy(&u->lock);
    free(u);
    local_release();
}

uint64_t fs_guid(const fs_unit *u) { return u ? u->guid : 0; }

/* Each transaction is addressed to the unit's node ID in the current bus generation, and retried when a bus
   reset happens in between (the node ID may change). */
#define RETRIES 3

static IOReturn target(fs_unit *u, uint32_t lo, FWAddress *a, UInt32 *gen) {
    UInt16 node = 0;
    IOReturn r = (*u->dev)->GetGenerationAndNodeID(u->dev, gen, &node);
    a->nodeID = node; a->addressHi = 0xFFFF; a->addressLo = lo;
    return r;
}

static int rq(fs_unit *u, uint32_t lo, uint32_t *out) {
    IOReturn r = kIOReturnError;
    for (int i = 0; i < RETRIES; i++) {
        FWAddress a; UInt32 gen, q = 0;
        if ((r = target(u, lo, &a, &gen))) continue;
        r = (*local)->ReadQuadlet(local, 0, &a, &q, true, gen);
        if (!r) { *out = OSSwapBigToHostInt32(q); return 0; }
    }
    return r;
}

static int rblock(fs_unit *u, uint32_t lo, UInt32 *buf, UInt32 n) {
    IOReturn r = kIOReturnError;
    for (int i = 0; i < RETRIES; i++) {
        FWAddress a; UInt32 gen, size = n * 4;
        if ((r = target(u, lo, &a, &gen))) continue;
        r = (*local)->Read(local, 0, &a, buf, &size, true, gen);
        if (!r && size != n * 4) r = kIOReturnUnderrun;
        if (!r) return 0;
    }
    return r;
}

static int wq(fs_unit *u, uint32_t lo, uint32_t value) {
    IOReturn r = kIOReturnError;
    for (int i = 0; i < RETRIES; i++) {
        FWAddress a; UInt32 gen;
        if ((r = target(u, lo, &a, &gen))) continue;
        r = (*local)->WriteQuadlet(local, 0, &a, OSSwapHostToBigInt32(value), true, gen);
        if (!r) return 0;
    }
    return r;
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
        UInt32 buf[16];
        if (rblock(u, FS_MIXER_BASE + offset + done * 4, buf, n)) { /* fallback: quadlet by quadlet */
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
    int r = wq(u, FS_MIXER_BASE + offset, value);
    pthread_mutex_unlock(&u->lock);
    return r;
}
