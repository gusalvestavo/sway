import AppKit

/// Sway's chimes (Resources/Sounds/<name>.m4a, made by tools/sounds.swift).
@MainActor
enum Sound: String {
    case headsUp = "heads-up"
    case breakStart = "break-start"
    case breakOver = "break-over"

    /// Loaded once and kept, so a sound isn't released while it plays.
    private static var cache: [Sound: NSSound] = [:]

    /// Plays at the volume from Settings, unless sounds are off.
    func play() {
        guard Settings.playSounds else { return }
        preview()
    }

    /// Plays even when sounds are off, e.g. to try out the volume in Settings.
    func preview() {
        guard let sound = Self.cache[self] ?? Self.load(self) else { return }
        sound.stop()
        sound.volume = Float(Settings.soundVolume)
        sound.play()
    }

    private static func load(_ sound: Sound) -> NSSound? {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "m4a", subdirectory: "Sounds"),
              let loaded = NSSound(contentsOf: url, byReference: true) else { return nil }
        cache[sound] = loaded
        return loaded
    }
}
