import Foundation

/// The languages Sway ships, as (lproj code, name in that language).
let supportedLanguages: [(code: String, name: String)] = [
    ("en", "English"), ("pt-BR", "Português (Brasil)"), ("es", "Español"), ("fr", "Français"),
    ("de", "Deutsch"), ("it", "Italiano"), ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"),
]

/// Where translations come from: the chosen language's .lproj, or the system's pick when nil.
nonisolated(unsafe) private var localizationBundle = bundle(for: Settings.language)
nonisolated(unsafe) private var localizationLocale = locale(for: Settings.language)

private func bundle(for code: String?) -> Bundle {
    guard let code, let path = Bundle.main.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path) else { return .main }
    return bundle
}

/// The language's locale, keeping the Mac's region (and with it the clock and date habits)
/// when the language doesn't name one, e.g. English with a 24-hour clock in Brazil.
private func locale(for code: String?) -> Locale {
    guard let code else { return .current }
    var components = Locale.Components(identifier: code)
    if components.region == nil { components.region = Locale.current.region }
    return Locale(components: components)
}

/// Switches the app's language right away; nil follows the Mac's language.
func applyLanguage(_ code: String?) {
    localizationBundle = bundle(for: code)
    localizationLocale = locale(for: code)
}

/// The locale matching the app's language, for formatters.
var appLocale: Locale { localizationLocale }

/// Localized text for `key`, the English wording, from Resources/<language>.lproj/Localizable.strings.
/// English is the fallback. Extra arguments fill `%d` / `%@` placeholders in the translation.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = localizationBundle.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, locale: localizationLocale, arguments: arguments)
}
