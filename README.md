# OpenControl for PreSonus FireStudio

**Logiciel libre de contrôle du mixeur DSP de la PreSonus FireStudio 26x26 (2008) sur macOS moderne.**
*Free replacement for FireControl / Universal Control for the original PreSonus FireStudio 26x26.*

PreSonus a arrêté le support de la FireStudio 26x26 en 2015. Avec les drivers FireWire d'un produit
plus récent, l'interface fonctionne encore en audio, mais plus aucun logiciel ne donne accès à son mixeur
interne : monitoring sans latence, routage des sorties, casques. OpenControl comble ce manque.

![FireStudio Mixer](docs/screenshot.png)

## Fonctions

- **9 mix stéréo** : 18 entrées et 18 retours DAW par mix, avec fader en dB, panoramique, mute, solo, liaison stéréo et master
- **Routage** de chaque paire de sorties (Out 1/2 … S/PDIF) vers une entrée, un retour DAW ou un mix ; source de Main et des 3 casques
- **Vu-mètres** à LED avec maintien de crête
- **6 presets** rappelables en un clic
- **Sauvegarde automatique** de l'état complet de la carte à chaque connexion, avec restauration
- Molette (±0,375 dB, ⇧ ×8), ⌥ pour le réglage fin, double-clic pour revenir à 0 dB / au centre

## Matériel et systèmes testés

| | |
|---|---|
| Interface | FireStudio 26x26 (modèle `0x08`, firmware DICE 1.0.4.0) |
| Mac | Intel, macOS 12.7.6, adaptateur Thunderbolt → FireWire |
| Drivers | PreSonus FireWire 4.2.1 (issus d'Universal Control 3.4.2) |

**Apple Silicon** : l'application est un Universal Binary, mais le kext PreSonus n'existe qu'en x86_64.
La prise en charge du FireWire sur Apple Silicon n'a pas été vérifiée.

## Installation

### A. Installeur complet (drivers + application), assemblé sur votre Mac

Ce dépôt **ne contient aucun binaire PreSonus**. Le script extrait les drivers de l'installeur officiel,
vérifie leur signature PreSonus et leur version, et les assemble sans modification avec l'application.

1. Téléchargez **Universal Control 3.4.2** pour macOS sur le site de PreSonus
   (`PreSonus_UniversalControl_v3_4_2_63992.dmg`).
2. Dans un clone du dépôt (outils en ligne de commande Xcode requis) :
   ```sh
   installer/build-installer.sh ~/Downloads/PreSonus_UniversalControl_v3_4_2_63992.dmg
   ```
3. Ouvrez `dist/OpenControl-FireStudio-<version>-complet.pkg`. Autorisez l'extension PreSonus dans
   *Sécurité et confidentialité* si macOS le demande, puis redémarrez.

L'installeur produit contient des drivers PreSonus : il est réservé à votre usage personnel et ne doit pas être redistribué.

### B. Application seule

Si les drivers sont déjà installés, téléchargez l'application depuis les
[Releases](../../releases) (`.pkg` ou `.zip`, Universal Binary).
Elle n'est pas notarisée : au premier lancement, faites un clic droit › *Ouvrir*.

### C. Depuis les sources

```sh
cd app
make ARCHS="x86_64 arm64"   # Universal Binary
make install                # copie dans /Applications
```

## Fonctionnement

L'application dialogue directement avec la puce DICE de la carte par des transactions FireWire
asynchrones (`IOFireWireLib`), sans passer par le driver audio. Le protocole est documenté dans
[docs/register-map.md](docs/register-map.md). Les outils de sonde en lecture/écriture se trouvent dans
[tools/probe](tools/probe).

L'accès FireWire est exclusif : fermez l'application avant d'utiliser les outils de sonde.

## Avertissement

OpenControl est un projet indépendant, **ni affilié ni approuvé par PreSonus**. « PreSonus »,
« FireStudio » et « Universal Control » sont des marques de leurs propriétaires respectifs. Le protocole
a été documenté à des fins d'interopérabilité avec un matériel dont le support a cessé. Le logiciel est
fourni sans garantie. Ses écritures sont limitées aux paramètres de mixage, et l'état de la carte est
sauvegardé avant toute modification.

## Remerciements

- [FFADO](https://ffado.org) et le driver Linux `snd-dice` (Takashi Sakamoto), pour la documentation de la puce DICE
- Le projet « Firestudio Catalina », pour l'idée de réutiliser les drivers d'un produit plus récent

## Licence

[MIT](LICENSE). Ne couvre que le code d'OpenControl, pas les drivers PreSonus.
