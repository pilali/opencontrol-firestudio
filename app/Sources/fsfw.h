// Accès FireWire minimal à la zone mixeur de la PreSonus FireStudio 26x26.
#ifndef FSFW_H
#define FSFW_H
#include <stdint.h>

#define FS_MIXER_BASE 0xE0700000u   /* adresse basse ; adresse haute 0xFFFF */
#define FS_MIXER_SIZE 0x1428u       /* octets */

/* 0 = OK. Ouvre la première FireStudio (vendor 0xA92, modèle 8) trouvée. */
int  fs_open(void);
void fs_close(void);
int  fs_is_open(void);
/* Lecture de `count` quadlets à partir de `offset` (octets, aligné sur 4), valeurs en ordre hôte. */
int  fs_read(uint32_t offset, uint32_t *out, uint32_t count);
/* Écriture d'un quadlet (ordre hôte). */
int  fs_write(uint32_t offset, uint32_t value);
/* Lecture d'un quadlet dans l'espace DICE (adresse basse absolue, haute 0xFFFF). */
int  fs_read_abs(uint32_t addrLo, uint32_t *out);
#endif
