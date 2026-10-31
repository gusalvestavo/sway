import AppKit

/// The first-launch window: a short welcome, then the work interval and break length.
@MainActor
final class Welcome: NSObject, NSWindowDelegate {
    /// The window closed, by finishing or early; the choices are already saved.
    var onFinish: () -> Void = {}

    private enum Step: Int, CaseIterable { case hello, work, breakLength, done }

    private var window: NSWindow?
    private let pageArea = NSView()
    private let bottomBar = NSStackView()
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let indicator = StepIndicator(count: Step.allCases.count)
    private var page: NSView?
    private var step = Step.hello
    /// Bumped on every page change, so reveals still pending from the old page are dropped.
    private var generation = 0
    private var finished = false

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        show(.hello, firstTime: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.title = L("Welcome to Sway")

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.controlSize = .large
        nextButton.target = self
        nextButton.action = #selector(goNext)
        nextButton.controlSize = .large
        nextButton.keyEquivalent = "\r"
        nextButton.useGlass(tint: SwayMark.sage)
        backButton.useGlass()

        // Back on the left, the step dots in the middle, Next on the right.
        let leading = NSView(), trailing = NSView()
        for (holder, button) in [(leading, backButton), (trailing, nextButton)] {
            button.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: holder.topAnchor),
                button.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                button === backButton
                    ? button.leadingAnchor.constraint(equalTo: holder.leadingAnchor)
                    : button.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            ])
        }
        bottomBar.setViews([leading, indicator, trailing], in: .center)
        bottomBar.distribution = .equalCentering
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        leading.widthAnchor.constraint(equalTo: trailing.widthAnchor).isActive = true
        leading.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let content = NSView()
        pageArea.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pageArea)
        content.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            pageArea.topAnchor.constraint(equalTo: content.topAnchor, constant: 36),
            pageArea.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 40),
            pageArea.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -40),
            pageArea.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -16),
            bottomBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            bottomBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            bottomBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
        ])
        window.contentView = content
        return window
    }

    // MARK: Steps

    private func show(_ step: Step, firstTime: Bool = false) {
        self.step = step
        generation += 1

        backButton.title = L("Go back")
        backButton.isHidden = step == .hello
        nextButton.title = step == .done ? L("Let's go!") : L("Next")
        indicator.current = step.rawValue
        indicator.setAccessibilityLabel(L("Step %d of %d", step.rawValue + 1, Step.allCases.count))

        // The old page fades out quickly; the new one comes in element by element.
        let hadPage = page != nil
        if let old = page {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                old.animator().alphaValue = 0
            }, completionHandler: { old.removeFromSuperview() })
        }
        let (stack, elements) = makePage(step)
        stack.translatesAutoresizingMaskIntoConstraints = false
        pageArea.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pageArea.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pageArea.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: pageArea.widthAnchor),
        ])
        page = stack
        // On the first appearance the bottom bar comes in last, after the page.
        reveal(firstTime ? elements + [bottomBar] : elements, after: hadPage ? 0.2 : 0)
    }

    /// The page's stack and its elements, top to bottom, in the order they appear.
    private func makePage(_ step: Step) -> (NSStackView, [NSView]) {
        let elements: [NSView]
        switch step {
        case .hello:
            let tagline = label(L("Find your flow."), size: 20, weight: .medium)
            tagline.textColor = Self.brandGreen
            elements = [MascotView(.happy, height: 120),
                        label(L("Welcome to Sway"), size: 28, weight: .bold),
                        tagline,
                        subtitle(L("Sometimes, all you need is a moment to clear your mind."))]
        case .work:
            elements = [MascotView(.focus, height: 84),
                        label(L("How long do you want to focus before a break?"), size: 22, weight: .bold),
                        subtitle(L("Sway will remind you when it's time to step away.")),
                        choices(SettingsWindow.workPresets, selected: Settings.workSeconds) { Settings.workSeconds = $0 }]
        case .breakLength:
            elements = [MascotView(.stretching, height: 84),
                        label(L("How long should your breaks be?"), size: 22, weight: .bold),
                        subtitle(L("Time to stand up, stretch and sway a little.")),
                        choices(SettingsWindow.breakPresets, selected: Settings.breakSeconds) { Settings.breakSeconds = $0 }]
        case .done:
            elements = [MascotView(.excited, height: 130),
                        label(L("You're good to go!"), size: 28, weight: .bold),
                        subtitle(L("You can customize Sway further anytime in Settings."))]
        }
        let stack = NSStackView(views: elements)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(18, after: elements[0])
        if elements.count == 4 { stack.setCustomSpacing(24, after: elements[2]) }
        return (stack, elements)
    }

    private static let brandGreen = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? SwayMark.leaf : SwayMark.sage
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.alignment = .center
        label.preferredMaxLayoutWidth = 440
        return label
    }

    private func subtitle(_ text: String) -> NSTextField {
        let subtitle = label(text, size: 14, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 380
        return subtitle
    }

    /// A row of tiles, one per preset; picking one saves it right away.
    private func choices(_ presets: [Int], selected: Int, save: @escaping (Int) -> Void) -> NSStackView {
        var tiles: [ChoiceTile] = []
        for seconds in presets {
            let tile = ChoiceTile(title: SettingsWindow.format(seconds))
            tile.isSelected = seconds == selected
            tile.onPick = {
                for other in tiles { other.isSelected = other === tile }
                save(seconds)
            }
            tiles.append(tile)
        }
        let row = NSStackView(views: tiles)
        row.spacing = 10
        return row
    }

    // MARK: Animation

    /// Fades the views in top to bottom; the bottom bar is kept, the rest stop once the page changes.
    private func reveal(_ views: [NSView], after start: TimeInterval) {
        let generation = generation
        Reveal.stagger(views, after: start) { [weak self] view in
            guard let self else { return false }
            return self.generation == generation || view === self.bottomBar
        }
    }

    // MARK: Actions

    @objc private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            window?.close()
            return
        }
        show(next)
    }

    @objc private func goBack() {
        if let previous = Step(rawValue: step.rawValue - 1) { show(previous) }
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        Settings.welcomed = true
        onFinish()
    }
}

/// One selectable duration on the welcome window; behaves like a radio button.
private final class ChoiceTile: NSControl {
    var onPick: () -> Void = {}
    var isSelected = false { didSet { needsDisplay = true; setAccessibilityValue(isSelected) } }

    private let label: NSTextField

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 82),
            heightAnchor.constraint(equalToConstant: 56),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 14
        layer.borderWidth = isSelected ? 0 : 1
        layer.borderColor = NSColor.separatorColor.cgColor
        layer.backgroundColor = isSelected ? SwayMark.sage.cgColor : NSColor.labelColor.withAlphaComponent(0.05).cgColor
        label.textColor = isSelected ? .white : .labelColor
    }

    override func mouseDown(with event: NSEvent) { pick() }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { pick() } else { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool { pick(); return true }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    private func pick() {
        isSelected = true
        onPick()
    }
}

/// Dots along the bottom of the welcome window; the current step is a wider sage pill.
private final class StepIndicator: NSView {
    private let count: Int
    var current = 0 { didSet { needsDisplay = true } }

    init(count: Int) {
        self.count = count
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private let dot: CGFloat = 8, wide: CGFloat = 22, gap: CGFloat = 8

    override var intrinsicContentSize: NSSize {
        NSSize(width: wide + CGFloat(count - 1) * (dot + gap), height: dot)
    }

    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0
        for index in 0..<count {
            let width = index == current ? wide : dot
            let rect = NSRect(x: x, y: (bounds.height - dot) / 2, width: width, height: dot)
            (index == current ? SwayMark.sage : NSColor.tertiaryLabelColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: dot / 2, yRadius: dot / 2).fill()
            x += width + gap
        }
    }
}
