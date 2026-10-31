import AppKit

private let peaceMessages = [
    "Breathe in slowly. Breathe out even slower.",
    "Nothing on that screen is going anywhere. You can rest.",
    "Look at something far away and let your eyes soften.",
    "Roll your shoulders back. Unclench your jaw.",
    "You've done enough for now. This moment is just for you.",
    "Stand up, stretch, and feel your feet on the ground.",
    "Drink some water. Your future self says thanks.",
    "Let your thoughts drift by like clouds.",
    "Rest is part of the work, not a break from it.",
    "Notice three things you can hear right now.",
    "Be gentle with yourself. You're doing fine.",
    "A calm mind solves problems faster. Let it settle.",
]

/// Full-screen overlay shown on every display while a break is running.
@MainActor
final class BreakOverlay: NSObject {
    var onEnd: () -> Void = {}
    var onPostpone: (Int) -> Void = { _ in }

    /// How long a break must run before it can be skipped.
    static let skipDelay: TimeInterval = 5
    /// Snooze choices in minutes, shared with the heads-up popover.
    static let snoozeOptions = [1, 3, 5]
    private var skipUnlocksAt = Date()

    private var windows: [NSWindow] = []
    private var panels: [OverlayPanel] = []
    private var message = ""
    private var title: String?
    private var total: TimeInterval = 1
    private var remaining: TimeInterval = 0
    private var finished = false

    private let fadeInDuration: TimeInterval = 0.6
    private let fadeOutDuration: TimeInterval = 0.4

    var isVisible: Bool { !windows.isEmpty }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// `title` names a planned break, e.g. "Lunch"; regular breaks show "Time for a break".
    func show(duration: TimeInterval, title: String? = nil) {
        self.title = title
        message = L(peaceMessages.randomElement()!)
        total = max(1, duration)
        remaining = duration
        finished = false
        skipUnlocksAt = Date().addingTimeInterval(Self.skipDelay)
        buildWindows(fadeIn: true)
    }

    func update(remaining: TimeInterval) {
        self.remaining = remaining
        render(animated: true)
    }

    func showFinished() {
        finished = true
        remaining = 0
        render(animated: true)
    }

    func close(animated: Bool = true) {
        let closing = windows
        windows = []
        panels = []
        guard animated else {
            closing.forEach { $0.orderOut(nil) }
            return
        }
        // Let clicks pass through while the overlay fades away, then remove it.
        closing.forEach { $0.ignoresMouseEvents = true }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            closing.forEach { $0.animator().alphaValue = 0 }
        }
        for window in closing {
            window.perform(#selector(NSWindow.orderOut(_:)), with: nil, afterDelay: fadeOutDuration)
        }
    }

    @objc private func screensChanged() {
        if isVisible { buildWindows(fadeIn: false) }
    }

    @objc fileprivate func endTapped() { onEnd() }

    @objc fileprivate func postponeTapped(_ sender: NSButton) { onPostpone(sender.tag) }

    @objc fileprivate func lockTapped() { ScreenLock.lock() }

    private func buildWindows(fadeIn: Bool) {
        close(animated: false)
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)

            // The first screen is the primary one (with the menu bar); the others are only blurred.
            if screen == NSScreen.screens.first {
                let panel = OverlayPanel(message: message, target: self, skipUnlocksAt: skipUnlocksAt)
                window.contentView = panel
                panels.append(panel)
            } else {
                window.contentView = BackdropView()
            }
            windows.append(window)
            window.alphaValue = fadeIn ? 0 : 1
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        render(animated: false)

        if fadeIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fadeInDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                windows.forEach { $0.animator().alphaValue = 1 }
            }
            // The backdrop, card and cat fade in first, then the card's contents.
            panels.forEach { $0.reveal(after: fadeInDuration / 2) }
        }
    }

    private func render(animated: Bool) {
        let progress = finished ? 1 : 1 - remaining / total
        for panel in panels {
            panel.update(progress: progress, remaining: remaining, finished: finished, title: title, animated: animated)
        }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Blurred, darkened backdrop that covers a whole screen.
private class BackdropView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Backdrop plus the logo progress, message and buttons; shown on the primary screen only.
private final class OverlayPanel: BackdropView {
    private static let contentWidth: CGFloat = 560
    private let ring = LogoProgressView()
    /// The cat sits on the card's top edge: stretching during the break, cheering once it's over.
    private let mascot = MascotView(.stretching, height: 110)
    private let timeLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel: NSTextField
    private let snoozeRow: NSStackView
    private let skipButton: NSButton
    private let lockButton: NSButton
    private let skipUnlocksAt: Date
    private var waitTimer: Timer?
    private var finished = false

    init(message: String, target: BreakOverlay, skipUnlocksAt: Date) {
        self.skipUnlocksAt = skipUnlocksAt
        messageLabel = NSTextField(wrappingLabelWithString: message)
        skipButton = Self.button(L("Skip break"), symbol: "forward.fill", target: target,
                                 action: #selector(BreakOverlay.endTapped))
        lockButton = Self.button(L("Lock screen"), symbol: "lock.fill", target: target,
                                 action: #selector(BreakOverlay.lockTapped))

        let snoozeButtons = BreakOverlay.snoozeOptions.map { minutes in
            let button = Self.button(L("+%d min", minutes), symbol: "zzz", target: target,
                                     action: #selector(BreakOverlay.postponeTapped(_:)))
            button.tag = minutes
            return button
        }
        snoozeRow = NSStackView(views: snoozeButtons)
        snoozeRow.spacing = 12

        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 20, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .light)
        timeLabel.textColor = .white
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        ring.addSubview(timeLabel)

        messageLabel.font = .systemFont(ofSize: 28, weight: .regular)
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.preferredMaxLayoutWidth = Self.contentWidth

        skipButton.bezelColor = SwayMark.sage
        skipButton.useGlass(tint: SwayMark.sage)

        let stack = NSStackView(views: [titleLabel, ring, messageLabel, snoozeRow, skipButton, lockButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 28
        stack.setCustomSpacing(40, after: messageLabel)
        stack.setCustomSpacing(24, after: snoozeRow)
        stack.setCustomSpacing(12, after: skipButton)
        // On macOS 26+ the content sits on a Liquid Glass card floating over the blur.
        let content = Glass.card(stack, cornerRadius: 40, padding: 48)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        addSubview(mascot)

        ring.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 260),
            ring.heightAnchor.constraint(equalToConstant: 260),
            timeLabel.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            // A fixed content width lets the message wrap predictably and sizes the full-width buttons.
            messageLabel.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            // Skip and Lock span the full width of the card's content.
            skipButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            lockButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            mascot.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            mascot.bottomAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        ])

        if Date() < skipUnlocksAt {
            let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(waitTick),
                              userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            waitTimer = timer
        }
        waitTick()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The cat and the card show right away; the break itself fades in, then the buttons.
    func reveal(after start: TimeInterval) {
        Reveal.stagger(groups: [[titleLabel, ring, messageLabel], [snoozeRow, skipButton, lockButton]], after: start)
    }

    func update(progress: Double, remaining: TimeInterval, finished: Bool, title: String?, animated: Bool) {
        self.finished = finished
        ring.setProgress(progress, animated: animated)
        let seconds = Int(remaining.rounded(.up))
        timeLabel.stringValue = finished ? "✓" : String(format: "%d:%02d", seconds / 60, seconds % 60)
        titleLabel.stringValue = finished ? L("Break's over") : title ?? L("Time for a break")
        mascot.pose = finished ? .cheering : .stretching
        snoozeRow.isHidden = finished
        lockButton.isHidden = finished
        waitTick()
    }

    /// While the break is too fresh to skip, a small ring in the Skip button's icon slot fills up.
    @objc private func waitTick() {
        let waitLeft = skipUnlocksAt.timeIntervalSinceNow
        if finished || waitLeft <= 0 {
            waitTimer?.invalidate()
            waitTimer = nil
            skipButton.isEnabled = true
            skipButton.title = finished ? L("Back to work") : L("Skip break")
            skipButton.image = Self.symbol(finished ? "checkmark" : "forward.fill")
        } else {
            skipButton.isEnabled = false
            skipButton.image = Self.waitRing(fraction: 1 - waitLeft / BreakOverlay.skipDelay)
        }
    }

    private static func button(_ title: String, symbol name: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, image: symbol(name) ?? NSImage(), target: target, action: action)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        if #available(macOS 26, *) { button.controlSize = .extraLarge } else { button.controlSize = .large }
        // Click-only: a keystroke typed as the break starts must not trigger anything.
        button.refusesFirstResponder = true
        button.useGlass()
        return button
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
    }

    /// A plain circular progress indicator, drawn as a template image so it takes the button's text colour.
    private static func waitRing(fraction: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.5
            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                    width: radius * 2, height: radius * 2))
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.25).setStroke()
            track.stroke()

            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                          endAngle: 90 - 360 * CGFloat(min(1, max(0, fraction))), clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Locks the screen like Control-Command-Q.
enum ScreenLock {
    static func lock() {
        // login.framework is private but has offered this call for many macOS releases.
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockScreen = @convention(c) () -> Int32
            _ = unsafeBitCast(symbol, to: LockScreen.self)()
            return
        }
        // Fallback: sleep the display, which locks when a password is required after sleep.
        let pmset = Process()
        pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmset.arguments = ["displaysleepnow"]
        try? pmset.run()
    }
}

/// Progress indicator in the shape of the Sway mark: the open arc fills clockwise
/// from half past one round to twelve, around the mark's thin inner circle.
private final class LogoProgressView: NSView {
    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let inner = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [inner, track, progress] {
            shape.fillColor = nil
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }
        track.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
        progress.strokeColor = SwayMark.leaf.cgColor
        progress.strokeEnd = 0
        inner.strokeColor = SwayMark.mist.withAlphaComponent(0.6).cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let lineWidth = size * SwayMark.lineRatio
        let radius = size / 2 - lineWidth / 2
        let degrees = CGFloat.pi / 180

        let arc = CGMutablePath()
        arc.addArc(center: center, radius: radius, startAngle: SwayMark.arcStart * degrees,
                   endAngle: SwayMark.arcEnd * degrees, clockwise: true)
        let innerRadius = radius * SwayMark.innerRadiusRatio

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for shape in [track, progress] {
            shape.frame = bounds
            shape.path = arc
            shape.lineWidth = lineWidth
        }
        inner.frame = bounds
        inner.lineWidth = lineWidth * SwayMark.innerLineRatio
        inner.path = CGPath(ellipseIn: CGRect(x: center.x - innerRadius, y: center.y - innerRadius,
                                              width: innerRadius * 2, height: innerRadius * 2), transform: nil)
        CATransaction.commit()
    }

    func setProgress(_ value: Double, animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(1)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        } else {
            CATransaction.setDisableActions(true)
        }
        progress.strokeEnd = min(1, max(0, value))
        CATransaction.commit()
    }
}
