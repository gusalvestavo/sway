import AppKit

/// The entrance shared by the welcome window and the break overlay: elements fade in
/// one after another, top to bottom, each drifting down a little into place.
@MainActor
enum Reveal {
    /// Pause between one element appearing and the next.
    static let delay: TimeInterval = 0.8
    static let fadeDuration: TimeInterval = 0.6

    /// Hides `views` and fades them in one by one, starting `start` seconds from now.
    /// `isCurrent` is checked before each fade, so a reveal for content that was replaced stops.
    static func stagger(_ views: [NSView], after start: TimeInterval = 0,
                        isCurrent: @escaping (NSView) -> Bool = { _ in true }) {
        stagger(groups: views.map { [$0] }, after: start, isCurrent: isCurrent)
    }

    /// Like `stagger(_:)`, but the views in each group fade in together.
    static func stagger(groups: [[NSView]], after start: TimeInterval = 0,
                        isCurrent: @escaping (NSView) -> Bool = { _ in true }) {
        for view in groups.joined() { view.alphaValue = 0 }
        for (index, group) in groups.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + start + Double(index) * delay) {
                for view in group where isCurrent(view) { fadeIn(view) }
            }
        }
    }

    static func fadeIn(_ view: NSView) {
        view.wantsLayer = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let drift = CABasicAnimation(keyPath: "transform.translation.y")
        drift.fromValue = 12  // Layers count y upward, so this starts slightly above.
        drift.toValue = 0
        drift.duration = fadeDuration
        drift.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer?.add(drift, forKey: "drift")
    }
}
