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

## Persistence

`/Library/Application Support/PaeFireStudio/PaeFireStudioDaemon` (launch daemon
`tc.tctechnologies.daemon.PaeFireStudio`) saves the driver settings when they change and restores them at boot:

- file `/Library/Preferences/PaeFireStudio.startup`;
- header: the ASCII string `PaeFireStudio%08lx` with the interface version (`PaeFireStudio00000007`), NUL-terminated (22 bytes);
- then the 0xA18-byte `DRIVER_RESTORE_SETTINGS` structure, little-endian: `+0x0` interface version (`0x1007`),
  `+0x4` operation mode, `+0x8` device GUID (64 bits), followed by other driver fields.

OpenControl never writes this file: it calls `SetOpMode` and lets the daemon save the result.

## Probe

`tools/probe/build/opmode` prints the current mode; `tools/probe/build/opmode 2` sets mode 2.
