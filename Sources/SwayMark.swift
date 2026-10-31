import AppKit

/// The Sway logo: an open sage arc around a thin inner circle.
enum SwayMark {
    static let sage = NSColor(srgbRed: 0x52 / 255, green: 0x74 / 255, blue: 0x5C / 255, alpha: 1)
    static let mist = NSColor(srgbRed: 0x9D / 255, green: 0xB3 / 255, blue: 0xA3 / 255, alpha: 1)
    /// Lighter sage that keeps enough contrast on dark backgrounds.
    static let leaf = NSColor(srgbRed: 0x8F / 255, green: 0xB3 / 255, blue: 0x9A / 255, alpha: 1)

    // Geometry, relative to the mark's size. The arc runs clockwise from `arcStart` round to
    // `arcEnd` (degrees, counter-clockwise from 3 o'clock), leaving a gap between twelve and
    // half past one that gives the mark its sense of movement.
    static let arcStart: CGFloat = 45
    static let arcEnd: CGFloat = 100
    static let lineRatio: CGFloat = 0.075
    static let innerRadiusRatio: CGFloat = 0.52
    static let innerLineRatio: CGFloat = 0.35

    /// Draws the mark centred in `rect`. `lineScale` thickens strokes for tiny sizes.
    static func draw(in rect: NSRect, outer: NSColor = sage, inner: NSColor = mist, lineScale: CGFloat = 1) {
        let size = min(rect.width, rect.height)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerWidth = size * lineRatio * lineScale
        let radius = size / 2 - outerWidth / 2

        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: arcStart, endAngle: arcEnd, clockwise: true)
        arc.lineWidth = outerWidth
        arc.lineCapStyle = .round
        outer.setStroke()
        arc.stroke()

        let innerRadius = radius * innerRadiusRatio
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - innerRadius, y: center.y - innerRadius,
                                                 width: innerRadius * 2, height: innerRadius * 2))
        circle.lineWidth = max(1, outerWidth * innerLineRatio)
        inner.setStroke()
        circle.stroke()
    }

    @MainActor static let menuBarImage = makeMenuBarImage(badge: nil)
    @MainActor static let pausedMenuBarImage = makeMenuBarImage(badge: .paused)
    @MainActor static let offHoursMenuBarImage = makeMenuBarImage(badge: .offHours)

    /// A small sign over the mark's top-right corner: a pause sign, or a beach umbrella outside work hours.
    private enum Badge { case paused, offHours }

    /// Template image for the menu bar, so macOS tints it for light and dark menu bars.
    private static func makeMenuBarImage(badge: Badge?) -> NSImage {
        let umbrella = NSImage(systemSymbolName: "beach.umbrella.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        // Outside work hours the image grows a little, so the umbrella stands over the mark's open gap.
        let size = badge == .offHours ? NSSize(width: 19, height: 18) : NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: NSRect(x: 1, y: 1, width: 14, height: 14), outer: .black,
                 inner: NSColor.black.withAlphaComponent(0.6), lineScale: 1.6)
            switch badge {
            case nil:
                break
            case .paused:
                // Clear a small disc so the badge stays legible where it overlaps the arc.
                let badgeCenter = NSPoint(x: rect.maxX - 4, y: rect.maxY - 4)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - 4, y: badgeCenter.y - 4, width: 8, height: 8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                for dx: CGFloat in [-1.9, 0.7] {
                    NSBezierPath(roundedRect: NSRect(x: badgeCenter.x + dx, y: badgeCenter.y - 2.6,
                                                     width: 1.2, height: 5.2),
                                 xRadius: 0.5, yRadius: 0.5).fill()
                }
            case .offHours:
                guard let umbrella else { break }
                let size = umbrella.size
                let frame = NSRect(x: rect.maxX - size.width, y: rect.maxY - size.height, width: size.width, height: size.height)
                // Cut a thin outline of the umbrella's own shape out of the mark, then draw it inside.
                for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 8) {
                    umbrella.draw(in: frame.offsetBy(dx: 1.2 * cos(angle), dy: 1.2 * sin(angle)),
                                  from: .zero, operation: .destinationOut, fraction: 1)
                }
                umbrella.draw(in: frame)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
