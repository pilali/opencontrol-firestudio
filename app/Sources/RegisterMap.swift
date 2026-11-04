// Carte des registres de la zone mixeur (base 0xFFFFE0700000), reconstituée par
// désassemblage de firestudiodevice.bundle (FireControl 2626, 2011) et lecture de l'appareil.
// Tous les décalages sont en octets depuis la base.

enum Reg {
    static let size: UInt32 = 0x1428
    static let quadlets = Int(size / 4)

    static let mixCount = 9
    static let inputCount = 18          // 8 analogiques, ADAT 1-8, S/PDIF L/R
    static let playbackCount = 18       // retours DAW (ou ADAT 9-16 en mode Expanded)
    static let outputCount = 18         // Out 1..16 + S/PDIF L/R
    static let stripStride: UInt32 = 12 // [niveau, pan, drapeaux]
    static let mixStride: UInt32 = 0xD8 // 18 tranches × 12

    /// Tranche d'entrée physique `ch` (0-17) dans le mix `mix` (0-8).
    static func inputStrip(mix: Int, ch: Int) -> UInt32 { 0x38 + UInt32(mix) * mixStride + UInt32(ch) * stripStride }
    /// Tranche de retour DAW `ch` (0-17) dans le mix `mix`.
    static func playbackStrip(mix: Int, ch: Int) -> UInt32 { 0x7D0 + UInt32(mix) * mixStride + UInt32(ch) * stripStride }
    /// Tranches « sortie » (27) : 0-17 = sorties physiques, 18-26 = maître des mix 1-9 (à confirmer).
    static func outputStrip(_ ch: Int) -> UInt32 { 0xF68 + UInt32(ch) * stripStride }

    // Mots d'une tranche
    static let level: UInt32 = 0      // 0…255 ; 255 = 0 dB, 0,375 dB par cran
    static let pan: UInt32 = 4        // 0…255, 0x7F = centre
    static let flags: UInt32 = 8      // 1 = mute, 2 = solo
    static let flagMute: UInt32 = 1
    static let flagSolo: UInt32 = 2

    /// Routage : source de la sortie physique `out` (0-17).
    static func outputSource(_ out: Int) -> UInt32 { 0x10AC + UInt32(out) * 4 }
    /// Main / Phones : paire de sorties copiée (valeur = 2 × paire). index 0 = Main, 1-3 = Phones 1-3.
    static func monitorSource(_ idx: Int) -> UInt32 { 0x10F4 + UInt32(idx) * 4 }
    /// Main / Phones remplacé par un mix : 0 = non, sinon mix + 1 (sans effet constaté hors mode MSR).
    static func monitorOverride(_ idx: Int) -> UInt32 {
        let slot = idx == 2 ? 3 : (idx == 3 ? 2 : idx)
        return 0x1104 + UInt32(slot) * 4
    }
    /// Masque de liaison stéréo d'un mix (bit p = paire d'entrées p, bit 16+p = paire DAW p).
    static func linkMask(mix: Int) -> UInt32 { 0x112C + UInt32(mix) * 4 }
    static let outputLinkMask: UInt32 = 0x1150

    // Réglages matériels (DeviceControls de FireControl)
    static let dcmt: UInt32 = 0x1114   // « Copy 1/2 to main L/R in surround mode »
    static let bnct: UInt32 = 0x1118   // « Terminate BNC » (word clock)
    static let clks: UInt32 = 0x111C   // dérivé de la source d'horloge (lecture seule ici)
    static let tbdo: UInt32 = 0x1120   // « Talkback to Digital Outs »
    static let mtss: UInt32 = 0x1124   // mute des mains en mode surround
    static let a2md: UInt32 = 0x1128   // « Expanded Mix Mode (ADAT 2) »
    static let dmmm: UInt32 = 0x1164   // mode de mixage (MSR)

    /// Noms : 53 champs de 12 octets à partir de 0x1168.
    /// 0-17 entrées, 18-35 retours, 36-44 mix 1-9, 45-52 noms DAW 11-18 de réserve.
    static let namesBase: UInt32 = 0x1168
    static let nameLength = 12
    static let nameCount = 53

    /// Vu-mètres : 60 octets à partir de 0x13E8 (lecture seule, rafraîchis par l'appareil).
    static let metersBase: UInt32 = 0x13E8
    static let meterQuadlets: UInt32 = 15

    /// Index du vu-mètre d'une entrée physique (0-17).
    static func inputMeter(_ ch: Int) -> Int {
        if ch < 8 { return ch + 8 }       // analogiques
        if ch < 16 { return ch - 8 }      // ADAT 1-8
        return ch + 18                    // S/PDIF
    }
    static func playbackMeter(_ ch: Int) -> Int { ch + 16 }
    static func mixMeter(_ mix: Int, right: Bool) -> Int { 40 + mix * 2 + (right ? 1 : 0) }
    /// Vu-mètre d'une source de routage (valeur de outputSource).
    static func sourceMeter(_ src: Int) -> Int? {
        switch src {
        case 0..<18: return inputMeter(src)
        case 18..<36: return playbackMeter(src - 18)
        case 36..<54: return src + 4
        default: return nil
        }
    }

    /// Plage autorisée à l'écriture : uniquement les paramètres.
    static let writableRange: Range<UInt32> = 0x38..<0x1168
}
