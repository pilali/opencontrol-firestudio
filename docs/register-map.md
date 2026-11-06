# DSP mixer register map — PreSonus FireStudio 26x26

Reconstructed by reading the device and by analysing, for interoperability purposes, the
`firestudiodevice.bundle` plugin shipped with FireControl 2626 (2011). No PreSonus code is reproduced here.

## Identification

| Item | Value |
|---|---|
| Vendor ID / Model ID | `0x000A92` / `0x000008` |
| Chip | TC Applied Technologies DICE (firmware 1.0.4.0, July 28, 2008) |
| DICE EAP protocol (`0xFFFFE0200000`) | **absent**: this firmware predates EAP |
| PreSonus mixer area | `0xFFFF E070 0000`, 0x1428 bytes (1290 quadlets) |

Access uses plain IEEE 1394 asynchronous transactions (quadlet reads/writes, big-endian on the bus).
They work from user space (`IOFireWireLib`) alongside the audio driver.

**Do not open the unit's `IOFireWireDevice` interface.** Opening it is exclusive, and IOFireWireFamily then
suspends and resumes the PreSonus driver attached to the unit, which restarts the audio streams. OpenControl
instead opens the Mac's own node (`IOFireWireLocalNode`) and sends each transaction to the unit's current node
ID, taken with the bus generation from the unit's interface, which stays unopened (`GetGenerationAndNodeID`,
`failOnReset` = true, retried after a bus reset).

**Release every IOFireWireLib interface before the process exits.** When a process exits with one still alive,
the kernel's cleanup resets the FireWire bus two or three times, 2 s apart, and the driver restarts the streams
after each reset. OpenControl releases them in an `atexit` handler and turns SIGTERM, SIGINT and SIGHUP into
`exit()`.

The firmware **stores the settings itself**: they survive a power cycle. Quadlet `0x0008` increments
on every write the firmware accepts.

## Header (`0x0000`–`0x0034`)

`13e 49 8b6 12 38 12 7d0 12 4 f68 9 1040 10ac 10f4`: sizes and pointers of the tables below
(18 inputs at `0x38`, 18 returns at `0x7D0`, 9 mixes, outputs at `0xF68`, routing at `0x10AC`, headphones at `0x10F4`).

## Channel strips (3 quadlets)

| Word | Content |
|---|---|
| `+0` | level 0–255 |
| `+4` | pan 0–255, `0x7F` = center |
| `+8` | flags: `1` = mute, `2` = solo |

**Level scale** (from `setMonitorConnection`): `level = 255 + 20·log10(gain) × 8/3`.
255 = 0 dB, 0.375 dB per step, 0 = −∞. Examples: 239 = −6 dB, 180 = −28 dB.

| Block | Strip address |
|---|---|
| Physical inputs (ch 0–17) | `0x038 + mix × 0xD8 + ch × 12` |
| DAW returns (ch 0–17) | `0x7D0 + mix × 0xD8 + ch × 12` |
| Outputs (27 strips) | `0xF68 + n × 12`: n 0–17 are the physical outputs, n 18–26 are the **masters of mixes 1–9** |

Inputs: 0–7 Mic/Line 1–8, 8–15 ADAT 1–8, 16–17 S/PDIF L/R.
Returns: DAW 1–18, or DAW 1–10 + ADAT 9–16 in *Expanded Mix Mode*.

## Stereo link

| Address | Content |
|---|---|
| `0x112C + mix × 4` | bit *p* = input pair *p* (0–8), bit 16 + *p* = return pair *p* |
| `0x1150` | bit *p* = output pair *p* |

The firmware only stores the flag. The user interface applies settings to both channels.

## Routing

| Address | Content |
|---|---|
| `0x10AC + out × 4` (18 words) | source of physical output `out`: 0–17 = direct input, 18–35 = DAW return, `36 + 2·mix` / `37 + 2·mix` = mix L / R |
| `0x10F4 + i × 4` | Main (i = 0) and Phones 1–3: copied output pair (value = 2 × pair) |
| `0x1104 + i × 4` | "overridden by mix" (0 = no, otherwise mix + 1; Phones 2 and 3 are swapped). **No audible effect** outside surround/MSR mode |

Typical zero-latency monitoring setup: Mix 1 → Out 1/2 (`0x10AC = 0x24`, `0x10B0 = 0x25`).
Main and the headphones copy Out 1/2.

## Hardware settings

| Address | FireControl code | Label |
|---|---|---|
| `0x1114` | `dcmt` | Copy 1/2 to main L/R in surround mode |
| `0x1118` | `bnct` | Terminate BNC |
| `0x111C` | `clks` | derived from the clock source (written by the driver) |
| `0x1120` | `tbdo` | Talkback to Digital Outs |
| `0x1124` | `mtss` | mains mute in surround mode |
| `0x1128` | `a2md` | Expanded Mix Mode (ADAT 2) |
| `0x1164` | `dmmm` | MSR mix mode |
| `0x1154`–`0x1164` | — | MSR state (read) |

These labels come from FireControl; their individual effect has not been verified.

## Channel names (`0x1168`, 53 × 12 bytes)

ASCII strings, least significant byte first in each quadlet (DICE convention).
0–17 inputs, 18–35 returns, 36–44 mixes 1–9, 45–52 spare DAW 11–18 names.

## Meters (`0x13E8`, 60 bytes, read only)

One byte per channel, least significant byte first. About `0x20` at rest, `0xA8` with a guitar played on IN1.

| Index | Source |
|---|---|
| 0–7 | ADAT 1–8 |
| 8–15 | Mic/Line 1–8 |
| 16–33 | DAW returns 1–18 |
| 34–35 | S/PDIF L/R |
| 40 + 2·mix (+1) | Mix 1–9 L (R) |

## Do not write

`0x0004` is the target of FireControl's `dfpg` command, whose meaning is unknown. The header, names
and meters must not be written either. The app and the `wq` tool refuse any write outside `0x0038`–`0x1167`.
