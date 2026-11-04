import Foundation

/// Localized string. Keys are the English texts; Resources/<lang>.lproj/Localizable.strings hold the
/// translations. Any system language without a translation falls back to English
/// (CFBundleDevelopmentRegion = en).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string, e.g. L("Read error (%d)", code). Numbers use the current locale.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}
