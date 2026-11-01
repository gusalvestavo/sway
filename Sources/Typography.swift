import AppKit
import CoreText

/// Fraunces, the soft serif in Resources/Fonts, for the app's larger display text.
/// Small UI text stays in the system font. Falls back to the system font if the file is missing.
enum Typography {
    /// Display text: titles, break messages and the welcome headings.
    static func display(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        font(size, weight: weight, monospacedDigits: false) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Countdown timers, with equal-width digits so the numbers don't shift as they tick.
    static func timer(_ size: CGFloat, weight: NSFont.Weight = .light) -> NSFont {
        font(size, weight: weight, monospacedDigits: true) ?? .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private static let base: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "Fraunces", withExtension: "ttf", subdirectory: "Fonts"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        else { return nil }
        return descriptors.first
    }()

    private static func font(_ size: CGFloat, weight: NSFont.Weight, monospacedDigits: Bool) -> NSFont? {
        guard let base else { return nil }
        // Axis tags of the variable font: weight, optical size, softness (0–100) and wonky letters (off).
        let variation: [NSNumber: NSNumber] = [
            tag("wght"): NSNumber(value: Double(cssWeight(weight))),
            tag("opsz"): NSNumber(value: Double(min(max(size, 9), 144))),
            tag("SOFT"): 100,
            tag("WONK"): 0,
        ]
        var attributes: [CFString: Any] = [kCTFontVariationAttribute: variation]
        if monospacedDigits {
            attributes[kCTFontFeatureSettingsAttribute] = [[
                kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector,
            ]]
        }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    /// Maps AppKit weights to the font's 100–900 weight axis.
    private static func cssWeight(_ weight: NSFont.Weight) -> Int {
        let steps: [NSFont.Weight] = [.thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]
        let index = steps.firstIndex { weight.rawValue < $0.rawValue } ?? steps.count
        return 100 + index * 100
    }

    private static func tag(_ name: String) -> NSNumber {
        NSNumber(value: name.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
}
