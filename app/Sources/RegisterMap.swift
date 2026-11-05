// Register map of the PreSonus mixer area (base 0xFFFFE0700000), reconstructed by reading the device
// and analysing firestudiodevice.bundle (FireControl 2626, 2011) for interoperability.
// All offsets are bytes from the base. See docs/register-map.md.

enum Reg {
    static let size: UInt32 = 0x1428
    /// DICE global section (low address, high 0xFFFF): +0x4C CLOCK_SELECT, +0x54 STATUS, +0x5C SAMPLE_RATE.
    static let diceGlobal: UInt32 = 0xE0000000 + 0x28
    static let quadlets = Int(size / 4)

    static let mixCount = 9
    static let inputCount = 18          // 8 analog, ADAT 1-8, S/PDIF L/R
    static let playbackCount = 18       // DAW returns (or ADAT 9-16 in Expanded Mix Mode)
    static let outputCount = 18         // Out 1..16 + S/PDIF L/R
    static let stripStride: UInt32 = 12 // [level, pan, flags]
    static let mixStride: UInt32 = 0xD8 // 18 strips × 12

    /// Physical input strip `ch` (0-17) in mix `mix` (0-8).
    static func inputStrip(mix: Int, ch: Int) -> UInt32 { 0x38 + UInt32(mix) * mixStride + UInt32(ch) * stripStride }
    /// DAW return strip `ch` (0-17) in mix `mix`.
    static func playbackStrip(mix: Int, ch: Int) -> UInt32 { 0x7D0 + UInt32(mix) * mixStride + UInt32(ch) * stripStride }
    /// Output strips (27): 0-17 = physical outputs, 18-26 = masters of mixes 1-9.
    static func outputStrip(_ ch: Int) -> UInt32 { 0xF68 + UInt32(ch) * stripStride }

    // Words of a strip
    static let level: UInt32 = 0      // 0…255; 255 = 0 dB, 0.375 dB per step
    static let pan: UInt32 = 4        // 0…255, 0x7F = center
    static let flags: UInt32 = 8      // 1 = mute, 2 = solo
    static let flagMute: UInt32 = 1
    static let flagSolo: UInt32 = 2

    /// Routing: source of physical output `out` (0-17).
    static func outputSource(_ out: Int) -> UInt32 { 0x10AC + UInt32(out) * 4 }
    /// Main / Phones: copied output pair (value = 2 × pair). index 0 = Main, 1-3 = Phones 1-3.
    static func monitorSource(_ idx: Int) -> UInt32 { 0x10F4 + UInt32(idx) * 4 }
    /// Main / Phones overridden by a mix: 0 = no, otherwise mix + 1 (no audible effect outside MSR mode).
    static func monitorOverride(_ idx: Int) -> UInt32 {
        let slot = idx == 2 ? 3 : (idx == 3 ? 2 : idx)
        return 0x1104 + UInt32(slot) * 4
    }
    /// Stereo link mask of a mix (bit p = input pair p, bit 16+p = DAW pair p).
    static func linkMask(mix: Int) -> UInt32 { 0x112C + UInt32(mix) * 4 }
    static let outputLinkMask: UInt32 = 0x1150

    // Hardware settings (FireControl DeviceControls)
    static let dcmt: UInt32 = 0x1114   // "Copy 1/2 to main L/R in surround mode"
    static let bnct: UInt32 = 0x1118   // "Terminate BNC" (word clock)
    static let clks: UInt32 = 0x111C   // derived from the clock source (read only here)
    static let tbdo: UInt32 = 0x1120   // "Talkback to Digital Outs"
    static let mtss: UInt32 = 0x1124   // mains mute in surround mode
    static let a2md: UInt32 = 0x1128   // "Expanded Mix Mode (ADAT 2)"
    static let dmmm: UInt32 = 0x1164   // MSR mix mode

    /// Names: 53 fields of 12 bytes from 0x1168.
    /// 0-17 inputs, 18-35 returns, 36-44 mixes 1-9, 45-52 spare DAW 11-18 names.
    static let namesBase: UInt32 = 0x1168
    static let nameLength = 12
    static let nameCount = 53

    /// Meters: 60 bytes from 0x13E8 (read only, refreshed by the device).
    static let metersBase: UInt32 = 0x13E8
    static let meterQuadlets: UInt32 = 15

    /// Meter index of a physical input (0-17).
    static func inputMeter(_ ch: Int) -> Int {
        if ch < 8 { return ch + 8 }       // analog
        if ch < 16 { return ch - 8 }      // ADAT 1-8
        return ch + 18                    // S/PDIF
    }
    static func playbackMeter(_ ch: Int) -> Int { ch + 16 }
    static func mixMeter(_ mix: Int, right: Bool) -> Int { 40 + mix * 2 + (right ? 1 : 0) }
    /// Meter of a routing source (value of outputSource).
    static func sourceMeter(_ src: Int) -> Int? {
        switch src {
        case 0..<18: return inputMeter(src)
        case 18..<36: return playbackMeter(src - 18)
        case 36..<54: return src + 4
        default: return nil
        }
    }

    /// Writable range: parameters only (header, names and meters are protected).
    static let writableRange: Range<UInt32> = 0x38..<0x1168
}
