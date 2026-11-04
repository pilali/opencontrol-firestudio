# OpenControl for PreSonus FireStudio

**Free software to control the DSP mixer of the original PreSonus FireStudio 26x26 (2008) on modern macOS.**
A replacement for FireControl / Universal Control, which no longer support this interface.

PreSonus ended support for the FireStudio 26x26 in 2015. With the FireWire drivers of a newer PreSonus
product the interface still works for audio, but no software can reach its internal mixer any more:
zero-latency monitoring, output routing and headphone feeds. OpenControl fills that gap.

![FireStudio Mixer](docs/screenshot.png)

## Features

- **9 stereo mixes**: 18 inputs and 18 DAW returns per mix, each with a fader in dB, pan, mute, solo, stereo link, plus a master fader
- **Routing**: send any input, DAW return or mix to each output pair (Out 1/2 … S/PDIF); choose the source of Main and the 3 headphone outputs
- **LED meters** with peak hold
- **6 presets** recalled with one click
- **Automatic backup** of the full device state on every connection, with restore
- Scroll wheel for fine steps (±0.375 dB, ⇧ ×8), ⌥-drag for fine adjustment, double-click to reset to 0 dB / center

## Tested hardware and systems

| | |
|---|---|
| Interface | FireStudio 26x26 (model `0x08`, DICE firmware 1.0.4.0) |
| Mac | Intel, macOS 12.7.6, Thunderbolt → FireWire adapter |
| Drivers | PreSonus FireWire 4.2.1 (from Universal Control 3.4.2) |

**Apple Silicon**: the app is a Universal Binary, but the PreSonus kext is x86_64 only.
FireWire support on Apple Silicon has not been verified.

## Installation

### A. Full installer (drivers + app), assembled on your Mac

This repository **contains no PreSonus binaries**. The script extracts the drivers from the official
installer, checks their PreSonus signature and version, and packages them unmodified together with the app.

1. Download **Universal Control 3.4.2** for macOS from the PreSonus website
   (`PreSonus_UniversalControl_v3_4_2_63992.dmg`).
2. In a clone of this repository (Xcode command line tools required):
   ```sh
   installer/build-installer.sh ~/Downloads/PreSonus_UniversalControl_v3_4_2_63992.dmg
   ```
3. Open `dist/OpenControl-FireStudio-<version>-full.pkg`. If macOS asks, allow the PreSonus system
   extension in *Security & Privacy*, then restart.

The resulting installer contains PreSonus drivers: keep it for your own use and do not redistribute it.

### B. App only

If the drivers are already installed, download the app from the [Releases](../../releases) page
(`.pkg` or `.zip`, Universal Binary). The app is not notarized: on first launch, right-click it and choose *Open*.

### C. From source

```sh
cd app
make ARCHS="x86_64 arm64"   # Universal Binary
make install                # copies the app to /Applications
```

## Languages

The app follows the macOS system language and falls back to English when that language is not included.
Included: English, Čeština, Dansk, Deutsch, Español, Français, Italiano, Magyar, Nederlands, Norsk bokmål,
Polski, Português (Brasil), Português (Portugal), Română, Suomi, Svenska, Türkçe.

Translations live in `app/Resources/<lang>.lproj/Localizable.strings`. The keys are the English texts.
Corrections from native speakers are welcome. `tools/check_l10n.py` (run by the CI) checks that every
language has every key, with matching format specifiers.

## How it works

The app talks directly to the DICE chip of the interface through asynchronous FireWire transactions
(`IOFireWireLib`), independently of the audio driver. The protocol is documented in
[docs/register-map.md](docs/register-map.md). Read/write probe tools are in [tools/probe](tools/probe).

FireWire access is exclusive: quit the app before using the probe tools.

## Disclaimer

OpenControl is an independent project, **not affiliated with or endorsed by PreSonus**. "PreSonus",
"FireStudio" and "Universal Control" are trademarks of their respective owners. The protocol was documented
for interoperability with hardware that is no longer supported. The software comes with no warranty. It only
writes mixer parameters, and it backs up the device state before any change.

## Acknowledgements

- [FFADO](https://ffado.org) and the Linux `snd-dice` driver (Takashi Sakamoto), for documenting the DICE chip
- The "Firestudio Catalina" project, for the idea of reusing the drivers of a newer product

## License

[MIT](LICENSE). Covers the OpenControl code only, not the PreSonus drivers.
