import AppKit

// Liquid Glass (macOS 26+). On older systems these fall back to the standard look.

extension NSButton {
    /// Glass bezel, optionally tinted (e.g. sage for the main action).
    func useGlass(tint: NSColor? = nil) {
        guard #available(macOS 26, *) else { return }
        bezelStyle = .glass
        if let tint { bezelColor = tint }
    }
}

enum Glass {
    /// Wraps `content` in a rounded glass card with `padding` around it,
    /// or returns `content` unchanged before macOS 26.
    static func card(_ content: NSView, cornerRadius: CGFloat, padding: CGFloat) -> NSView {
        guard #available(macOS 26, *) else { return content }

        let inner = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: inner.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -padding),
        ])

        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = inner
        return glass
    }
}
