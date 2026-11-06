// Minimal FireWire access to the mixer area of PreSonus FireStudio 26x26 units.
// Several units can be open at the same time; each one is identified by its 64-bit GUID.
#ifndef FSFW_H
#define FSFW_H
#include <stdint.h>

#define FS_MIXER_BASE 0xE0700000u   /* low address; high address is 0xFFFF */
#define FS_MIXER_SIZE 0x1428u       /* bytes */

typedef struct fs_unit fs_unit;     /* one open unit (opaque) */

/* Lists the FireStudio 26x26 units on the bus (vendor 0xA92, model 8). Returns the number found
   (at most `max` GUIDs are written). */
int  fs_list(uint64_t *guids, int max);

/* Opens the unit with this GUID (0 = the first one found). The unit itself is not opened (that would restart
   the audio streams): transactions go through the Mac's local FireWire node. On failure returns NULL and sets
   *err: -1 not found, -2 plug-in error, -3 local node unavailable. */
fs_unit *fs_open(uint64_t guid, int *err);
void     fs_close(fs_unit *u);
uint64_t fs_guid(const fs_unit *u);

/* Reads `count` quadlets from `offset` (bytes, 4-aligned); values in host byte order. */
int  fs_read(fs_unit *u, uint32_t offset, uint32_t *out, uint32_t count);
/* Writes one quadlet (host byte order). Refused outside the parameter range 0x38-0x1167. */
int  fs_write(fs_unit *u, uint32_t offset, uint32_t value);
/* Reads one quadlet in the DICE space (absolute low address, high address 0xFFFF). */
int  fs_read_abs(fs_unit *u, uint32_t addrLo, uint32_t *out);
#endif
