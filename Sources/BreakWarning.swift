import AppKit

/// Small popover under the menu bar item that says a break is coming up.
@MainActor
final class BreakWarning: NSObject {
    var onStartNow: () -> Void = {}
    var onPostpone: () -> Void = {}

    private let popover = NSPopover()
    private let titleLabel = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    /// The popover hides itself after this long so it never lingers.
    private let visibleSeconds: TimeInterval = 12

    var isShown: Bool { popover.isShown }

    override init() {
        super.init()

        let mark = NSImage(size: NSSize(width: 28, height: 28), flipped: false) { rect in
            SwayMark.draw(in: rect.insetBy(dx: 1, dy: 1), lineScale: 1.3)
            return true
        }
        let icon = NSImageView(image: mark)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Start wrapping up what you're doing.")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let text = NSStackView(views: [titleLabel, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let header = NSStackView(views: [icon, text])
        header.spacing = 10

        let startNow = NSButton(title: "Start now", target: self, action: #selector(startNowTapped))
        let postpone = NSButton(title: "Postpone 5 min", target: self, action: #selector(postponeTapped))
        for button in [startNow, postpone] { button.controlSize = .small }
        startNow.useGlass(tint: SwayMark.sage)
        postpone.useGlass()
        let buttons = NSStackView(views: [startNow, postpone])
        buttons.spacing = 6

        let stack = NSStackView(views: [header, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        let controller = NSViewController()
        controller.view = stack
        popover.contentViewController = controller
        popover.behavior = .semitransient
        popover.animates = true
    }

    func show(relativeTo button: NSStatusBarButton, remaining: TimeInterval) {
        update(remaining: remaining)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(timeInterval: visibleSeconds, target: self,
                                         selector: #selector(hideTimerFired), userInfo: nil, repeats: false)
    }

    func update(remaining: TimeInterval) {
        let seconds = max(0, Int(remaining.rounded(.up)))
        titleLabel.stringValue = String(format: "Break in %d:%02d", seconds / 60, seconds % 60)
    }

    func close() {
        hideTimer?.invalidate()
        hideTimer = nil
        if popover.isShown { popover.close() }
    }

    @objc private func hideTimerFired() { close() }

    @objc private func startNowTapped() {
        close()
        onStartNow()
    }

    @objc private func postponeTapped() {
        close()
        onPostpone()
    }
}
