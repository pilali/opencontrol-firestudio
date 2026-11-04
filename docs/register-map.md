# Carte des registres du mixeur DSP — PreSonus FireStudio 26x26

Reconstituée par lecture de l'appareil et par analyse, à des fins d'interopérabilité, du plugin
`firestudiodevice.bundle` livré avec FireControl 2626 (2011). Aucun code PreSonus n'est reproduit ici.

## Identification

| Élément | Valeur |
|---|---|
| Vendor ID / Model ID | `0x000A92` / `0x000008` |
| Puce | TC Applied Technologies DICE (firmware 1.0.4.0, 28 juillet 2008) |
| Protocole EAP DICE (`0xFFFFE0200000`) | **absent** : ce firmware est antérieur à EAP |
| Zone mixeur PreSonus | `0xFFFF E070 0000`, 0x1428 octets (1290 quadlets) |

Les accès sont de simples transactions asynchrones IEEE 1394 (lecture/écriture de quadlets,
big-endian sur le bus). Ils fonctionnent depuis l'espace utilisateur (`IOFireWireLib`) en parallèle du
driver audio. L'ouverture de l'interface `IOFireWireDevice` est exclusive entre clients utilisateur.

Le firmware **mémorise lui-même** les réglages : ils survivent à l'extinction. Le quadlet `0x0008`
s'incrémente à chaque écriture prise en compte.

## En-tête (`0x0000`–`0x0034`)

`13e 49 8b6 12 38 12 7d0 12 4 f68 9 1040 10ac 10f4` — tailles et pointeurs des tables ci-dessous
(18 entrées à `0x38`, 18 retours à `0x7D0`, 9 mix, sorties à `0xF68`, routage à `0x10AC`, casques à `0x10F4`).

## Tranches de console (3 quadlets)

| Mot | Contenu |
|---|---|
| `+0` | niveau 0–255 |
| `+4` | panoramique 0–255, `0x7F` = centre |
| `+8` | drapeaux : `1` = mute, `2` = solo |

**Échelle du niveau** (tirée de `setMonitorConnection`) : `niveau = 255 + 20·log10(gain) × 8/3`.
255 = 0 dB, 0,375 dB par cran, 0 = −∞. Exemples : 239 = −6 dB, 180 = −28 dB.

| Bloc | Adresse de la tranche |
|---|---|
| Entrées physiques (ch 0–17) | `0x038 + mix × 0xD8 + ch × 12` |
| Retours DAW (ch 0–17) | `0x7D0 + mix × 0xD8 + ch × 12` |
| Sorties (27 tranches) | `0xF68 + n × 12` — n 0–17 : sorties physiques ; n 18–26 : **master des mix 1–9** |

Entrées : 0–7 Mic/Line 1–8, 8–15 ADAT 1–8, 16–17 S/PDIF L/R.
Retours : DAW 1–18, ou DAW 1–10 + ADAT 9–16 en *Expanded Mix Mode*.

## Liaison stéréo (Link)

| Adresse | Contenu |
|---|---|
| `0x112C + mix × 4` | bit *p* = paire d'entrées *p* (0–8), bit 16 + *p* = paire de retours *p* |
| `0x1150` | bit *p* = paire de sorties *p* |

Le firmware ne fait que mémoriser l'indicateur. C'est l'interface qui applique les réglages aux deux canaux.

## Routage

| Adresse | Contenu |
|---|---|
| `0x10AC + out × 4` (18 mots) | source de la sortie physique `out` : 0–17 = entrée directe, 18–35 = retour DAW, `36 + 2·mix` / `37 + 2·mix` = mix L / R |
| `0x10F4 + i × 4` | Main (i = 0) et Phones 1–3 : paire de sorties recopiée (valeur = 2 × paire) |
| `0x1104 + i × 4` | « remplacé par un mix » (0 = non, sinon mix + 1 ; Phones 2 et 3 croisés). **Sans effet constaté** hors mode surround/MSR |

Configuration typique de monitoring sans latence : Mix 1 → Out 1/2 (`0x10AC = 0x24`, `0x10B0 = 0x25`).
Main et les casques recopient Out 1/2.

## Réglages matériels

| Adresse | Code FireControl | Libellé |
|---|---|---|
| `0x1114` | `dcmt` | Copy 1/2 to main L/R in surround mode |
| `0x1118` | `bnct` | Terminate BNC |
| `0x111C` | `clks` | dérivé de la source d'horloge (écrit par le driver) |
| `0x1120` | `tbdo` | Talkback to Digital Outs |
| `0x1124` | `mtss` | mute des mains en mode surround |
| `0x1128` | `a2md` | Expanded Mix Mode (ADAT 2) |
| `0x1164` | `dmmm` | mode de mixage MSR |
| `0x1154`–`0x1164` | — | état MSR (lecture) |

Ces libellés viennent de FireControl ; leur effet n'a pas été vérifié individuellement.

## Noms des canaux (`0x1168`, 53 × 12 octets)

Chaînes ASCII, octets de poids faible en premier dans chaque quadlet (convention DICE).
0–17 entrées, 18–35 retours, 36–44 mix 1–9, 45–52 noms DAW 11–18 de réserve.

## Vu-mètres (`0x13E8`, 60 octets, lecture seule)

Un octet par canal, octet de poids faible en premier. Environ `0x20` au repos, `0xA8` avec une guitare jouée sur IN1.

| Index | Source |
|---|---|
| 0–7 | ADAT 1–8 |
| 8–15 | Mic/Line 1–8 |
| 16–33 | retours DAW 1–18 |
| 34–35 | S/PDIF L/R |
| 40 + 2·mix (+1) | Mix 1–9 L (R) |

## À ne pas écrire

`0x0004` est la cible de la commande `dfpg` de FireControl, de sens inconnu. L'en-tête, les noms et les
vu-mètres ne doivent pas être écrits non plus. L'application refuse toute écriture hors de `0x0038`–`0x1167`.
