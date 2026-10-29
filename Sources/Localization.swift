import Foundation

/// Localized text for `key`, the English wording, from Resources/<language>.lproj/Localizable.strings.
/// English is the fallback. Extra arguments fill `%d` / `%@` placeholders in the translation.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, locale: .current, arguments: arguments)
}
