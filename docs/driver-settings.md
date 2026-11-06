# PreSonus driver settings (operation mode)

Universal Control used to offer an *operation mode* for the FireStudio: a trade-off between latency and
robustness against dropouts. The setting does not live in the interface but in the PreSonus FireWire audio
driver (`PaeFireStudio.kext` 4.2.1, a TC Applied Technologies DICE driver). This page documents how
OpenControl reaches it. Nothing here writes to the interface.

## User client

| | |
|---|---|
| Service class | `PaeFireStudio` |
| `IOServiceOpen` type | any (the driver flags `0x7380` and `0x9106` as its own control panel and daemon) |
| Privileges | none (works as a normal user) |

Dispatch table (`PaeFireStudioUserClient::externalMethod`), the entries used by OpenControl:

| Selector | Method | Input | Output |
|---|---|---|---|
| 0 | GetVersion | — | 2 scalars (`[1]` = interface version `0x1007`) |
| 12 | GetAudioErrorCount | — | 0x20-byte struct (see below) |
| 13 | ClearAudioErrorCount | — | — |
| 7 | GetOpMode | — | 4-byte struct (`uint32` mode) |
| 8 | SetOpMode | 4-byte struct (`uint32` mode, 0–3) | — |
| 25 | GetDriverSettings | — | 0xA18-byte struct |
| 26 | RestoreDriverSettings | 0xA18-byte struct | — |

`SetOpMode` rejects values above 3, notifies the clients and restarts streaming (an audible gap of about one second).

## Modes

The driver's default is mode 1. `UpdateIsochBufferParams` sizes the isochronous buffers from the mode,
with a few extra cycles above 88.2 and 176.4 kHz. The safety offsets the driver then reports to Core Audio,
measured at 48 kHz:

| Mode | Output safety offset | Input safety offset |
|---|---|---|
| 0 | 16 samples | 112 samples |
| 1 (default) | 48 | 128 |
| 2 | 80 | 144 |
| 3 | 112 | 160 |

They are visible in the I/O Registry as `IOAudioEngineSampleOffset` and `IOAudioEngineInputSampleOffset`
on `PaeFireStudioAudioEngine`. The labels in OpenControl (Lowest latency, Normal, Safe, Safest) are descriptive;
the original Universal Control names are not known.

## Stream error counters

`GetAudioErrorCount` returns three `uint32` counters, reset when the driver loads and by `ClearAudioErrorCount`:

| Offset | Incremented in | Meaning |
|---|---|---|
| `+0x10` | `ReadFirewireBuffers` | receive errors (recording stream) |
| `+0x18` | `FillFirewireBuffers` | transmit errors (playback stream) |
| `+0x1C` | `SendGroupCallback` | late transmit callbacks (timing) |

OpenControl shows their sum, polled every 2 s while the Settings page is open.

## Clock source

The driver publishes the clock sources to Core Audio (`kAudioDevicePropertyClockSource`, device UID
`PaeFireStudioAudioEngine:0`), the same setting as in Audio MIDI Setup. Core Audio item *n* writes DICE
source *n* to `CLOCK_SELECT` for 0–7; item 8 writes the internal clock (DICE `0x0C`).

**The names are wrong.** They come from the device (DICE global `CLOCK_SOURCE_NAMES`:
`SPDIF\ADAT\Word Clock\Unused\Unused\Unused\Unused\Internal`) and are applied to items 0–7 in order,
but the sources follow the standard DICE numbering (0–3 AES receivers 1–4, 5 ADAT, 7 word clock). Measured
mapping:

| Core Audio item | Driver name | DICE `CLOCK_SELECT` | Real source | Verified |
|---|---|---|---|---|
| 0 | S/PDIF | `0x200` | S/PDIF input (AES receiver 1) | FireControl's clock map; not tested |
| 1 | ADAT | `0x201` | AES receiver 2, not wired on the FireStudio | never locks |
| 2 | Word Clock | `0x202` | AES receiver 3, not wired on the FireStudio | never locks |
| 3, 4, 6 | Unused | — | — | — |
| 5 | Unused | `0x205` | **ADAT**, port chosen by mixer register `0x111C` | yes (ADAT 1) |
| 7 | Internal | `0x207` | **Word clock** (BNC) | yes |
| 8 | Internal | `0x20C` | internal clock | yes |

FireControl 2626 confirms this mapping: its clock map (`Presonus::gClockMap` in `firestudiodevice.bundle`) is
Internal → 12, BNC → 7, S/PDIF → 0, ADAT 1 → 5, ADAT 2 → 5. For ADAT, FireControl then writes the mixer
register `0x111C` (`clks`): 0 for ADAT 1, 1 for ADAT 2, which selects the optical port the unit syncs to.

OpenControl offers Internal (8), S/PDIF (0), ADAT 1 (5, `0x111C` = 0), ADAT 2 (5, `0x111C` = 1) and
Word Clock (7). The register is written on the clock master. ADAT 2 has not been tested yet.

How this was verified: a second FireStudio, standalone on its internal clock, sends ADAT (both optical ports)
and word clock (BNC) to the unit under test, which runs alone on the bus at 48 kHz.

- Items 1 and 2 never lock, at 44.1, 48, 88.2 or 96 kHz. With the ADAT signal present, EXT_STATUS shows ADAT
  received (`0x10`) and ADAT slipping (`0x00100000`).
- Item 7 locks, and the ADAT slip bit clears: the unit now runs at the rate of the other one. Unplugging the
  BNC cable unlocks it and the slip comes back; plugging it in again locks it.
- Item 5 locks with the BNC cable unplugged, with no ADAT slip.
- On the internal clock (item 8), the ADAT signal of the other unit slips, as expected from two free-running
  clocks.

## Sample rate

Set through Core Audio (`kAudioDevicePropertyNominalSampleRate`), like the clock source: 44.1, 48, 88.2 or
96 kHz. The driver applies it to every unit of the bus and restarts streaming.

A unit disconnected from the FireWire bus keeps its rate while it stays powered on, but the rate is not stored:
after a power cycle without a computer it runs at 44.1 or 48 kHz (the LED blinks slowly while it looks for a
clock, very fast at 96 kHz). The firmware stores the mixer area in flash, not the DICE clock settings.

The lock state is read over FireWire in the DICE global section (`0xFFFFE0000028`, offset given by quadlet 0
of the DICE space): `+0x54` STATUS, bit 0 = locked, bits 8–15 = nominal rate index; `+0x5C` SAMPLE_RATE in Hz.
`+0x58` EXT_STATUS reads `0xC0` on internal clock (the two receive streams from the Mac); bit `0x10` = ADAT
signal received, bit `0x00100000` = ADAT slip (the ADAT signal does not run at the unit's rate). While unlocked the
DICE stops the streams (ENABLE = 0) and the interface is silent.

## Several units on the bus

The driver aggregates up to **5** DICE devices of the same family found on the FireWire bus into **one**
Core Audio device: their channels are concatenated, one unit is the clock master and the others follow it
over FireWire. The layouts below come from the disassembly of `PaeFireStudio.kext` 4.2.1.

Observed with two FireStudio 26x26 units (firmware 1.0.4.0) daisy-chained on one bus: one Core Audio device
with 52 inputs and 52 outputs, slots 0 and 1, both nicknamed `FIRESTUDIO` by default. The master runs on its
selected clock (DICE `CLOCK_SELECT` source `0x0C`, internal); the other unit is set to source `0x08` (ARX1,
the isochronous stream received from the Mac) and reports itself locked. The DICE global `+0x64` register
reads `0x01000400` on both units: firmware 1.0.4.0.

OpenControl lists the units in *Settings → Units* (shown when more than one unit is present): driver nickname,
GUID, clock role and lock state of each unit, a button to make a unit the clock master (`SetMaster`, after a
confirmation) and renaming (`SetNickName`). The unit shown in the mixer is chosen in the window header.

Both were tested with two units: `SetNickName` renames the unit at once, and `SetMaster` causes a short audio gap
before playback resumes, the other unit then following the new master. The PreSonus daemon saves the names and
the master GUID in `PaeFireStudio.startup`, so the chosen master stays the preferred one: when the master is
powered off the remaining unit takes over on its internal clock, and the preferred master gets its role back
as soon as it reappears on the bus. Units take driver slots, and therefore Core Audio channel ranges (1–26,
27–52…), in the order the driver finds them.

**Driver bug: switching off the unit in slot 0.** When the unit in driver slot 0 disappears while another unit
stays on, the remaining unit keeps its slot (1) and the driver's audio engine stays paused
(`IOAudioEngineState` = 2 on `PaeFireStudioAudioEngine`): no audio reaches the interface, even after relaunching
the audio application. A bus reset, `SetOpMode` or a sample rate change do not resume it. Unplugging the FireWire
cable from the Mac for a few seconds does: the driver forgets every unit and the remaining one takes slot 0.
OpenControl shows a warning with this advice when the engine stays paused for five seconds. To avoid it, switch
all units off together.

### `GetConfigInfo` (selector 3, 0xEE8-byte struct out, `BUS_CONFIG`)

| Offset | Content |
|---|---|
| `+0x000` | `uint64` GUID of the clock master |
| `+0x00C` | current clock source (DICE index, `0x0C` = internal) |
| `+0x010` | current rate index (2 = 48 kHz) |
| `+0x014` | supported rates mask (`0x1E` = 44.1 / 48 / 88.2 / 96 kHz) |
| `+0x018` | supported clock sources mask (`0x10FF` = sources 0–7 and 12) |
| `+0x020` | 13 clock source names × 0x100 bytes |
| `+0xD20` | 5 device entries × 0x58 bytes (see below); unused entries have GUID `0xFFFF…` and slot `0xFFFFFFFF` |
| `+0xED8` | number of devices |
| `+0xEDC` | total input channels (26 per FireStudio) |
| `+0xEE0` | total output channels |

Device entry (0x58 bytes): `+0x00` `uint64` GUID, `+0x08` nickname (64 bytes, NUL-terminated),
`+0x48` state (1 with one unit online), `+0x4C` driver slot index (0–4), `+0x50` unknown (1).

Devices excluded with `SetDeviceState` are not listed.

### Setters

| Selector | Method | Input | Effect |
|---|---|---|---|
| 5 | SetSync | `uint32` DICE clock source index | clock source of the master (rejected if not in the supported mask); restarts streaming. Same effect as the Core Audio clock source. |
| 6 | SetMaster | 8-byte struct: `uint64` GUID | requests that unit as clock master; applied at the next streaming restart (triggered immediately) |
| 17 | SetNickName | 0x200-byte struct (in and out): `+0x000` `uint32` slot index (0–4), `+0x1C0` name (64 bytes) | renames the unit (stored in the nickname table, persisted); returns `+0x04` slot and `+0x08` the updated device info |
| 19 | SetDeviceState | 8 bytes: `uint32` state, `uint32` slot index | state 5 excludes the unit from the aggregate (its GUID goes to the disabled table, 32 entries); any other value re-enables it |
| 10 | GetNicknameTable | — | 0x900 bytes: 32 entries × 0x48 (`uint64` GUID + 64-byte name) |
| 11 | GetDisabledDevicesTable | — | 0x100 bytes: 32 `uint64` GUIDs |

`SetClock` (4) takes a `uint32` too and is not documented here yet.

### Persisted settings (`DRIVER_RESTORE_SETTINGS`, 0xA18 bytes)

| Offset | Content |
|---|---|
| `+0x000` | interface version `0x1007` |
| `+0x004` | operation mode |
| `+0x008` | `uint64` GUID of the clock master in use |
| `+0x010` | clock source (DICE index) |
| `+0x014` | rate index |
| `+0x018` | nickname table (0x900 bytes, as `GetNicknameTable`) |
| `+0x918` | disabled devices table (0x100 bytes, as `GetDisabledDevicesTable`) |

## Persistence

`/Library/Application Support/PaeFireStudio/PaeFireStudioDaemon` (launch daemon
`tc.tctechnologies.daemon.PaeFireStudio`) saves the driver settings when they change and restores them at boot:

- file `/Library/Preferences/PaeFireStudio.startup`;
- header: the ASCII string `PaeFireStudio%08lx` with the interface version (`PaeFireStudio00000007`), NUL-terminated (22 bytes);
- then the 0xA18-byte `DRIVER_RESTORE_SETTINGS` structure, little-endian (layout above).

OpenControl never writes this file: it calls `SetOpMode` and lets the daemon save the result.

## Probe

`tools/probe/build/opmode` prints the current mode; `tools/probe/build/opmode 2` sets mode 2.
