// Minimal FireWire access to the mixer area of the PreSonus FireStudio 26x26.
#ifndef FSFW_H
#define FSFW_H
#include <stdint.h>

#define FS_MIXER_BASE 0xE0700000u   /* low address; high address is 0xFFFF */
#define FS_MIXER_SIZE 0x1428u       /* bytes */

/* 0 = OK. Opens the first FireStudio found (vendor 0xA92, model 8). */
int  fs_open(void);
void fs_close(void);
int  fs_is_open(void);
/* Reads `count` quadlets from `offset` (bytes, 4-aligned); values in host byte order. */
int  fs_read(uint32_t offset, uint32_t *out, uint32_t count);
/* Writes one quadlet (host byte order). Refused outside the parameter range 0x38-0x1167. */
int  fs_write(uint32_t offset, uint32_t value);
/* Reads one quadlet in the DICE space (absolute low address, high address 0xFFFF). */
int  fs_read_abs(uint32_t addrLo, uint32_t *out);
#endif
