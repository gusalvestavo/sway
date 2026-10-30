import AppKit

/// Small popover under the menu bar item that says a break is coming up.
@MainActor
final class BreakWarning: NSObject {
    var onStartNow: () -> Void = {}
    /// Adds the given number of minutes to the countdown.
    var onSnooze: (Int) -> Void = { _ in }

    private let popover = NSPopover()
    private let titleLabel = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    /// The popover hides itself after this long so it never lingers.
    private let visibleSeconds: TimeInterval = 12

    var isShown: Bool { popover.isShown }

    override init() {
        super.init()

        let icon = MascotView(.getReady, height: 44)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let subtitle = NSTextField(labelWithString: L("Start wrapping up what you're doing."))
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let text = NSStackView(views: [titleLabel, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let header = NSStackView(views: [icon, text])
        header.spacing = 10

        let startNow = NSButton(title: L("Start now"), target: self, action: #selector(startNowTapped))
        startNow.controlSize = .small
        startNow.useGlass(tint: SwayMark.sage)

        // Same snooze choices as the break overlay.
        let zzz = NSImage(systemSymbolName: "zzz", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        let snoozeButtons = BreakOverlay.snoozeOptions.map { minutes in
            let button = NSButton(title: L("+%d min", minutes), image: zzz ?? NSImage(), target: self,
                                  action: #selector(snoozeTapped(_:)))
            button.tag = minutes
            button.imagePosition = .imageLeading
            button.controlSize = .small
            button.useGlass()
            return button
        }
        let buttons = NSStackView(views: [startNow] + snoozeButtons)
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
        // Size the popover to its content so the button row is never clipped.
        if let content = popover.contentViewController?.view {
            content.layoutSubtreeIfNeeded()
            // Glass buttons draw slightly wider than their layout size, so add the trailing margin back.
            let fitting = content.fittingSize
            popover.contentSize = NSSize(width: fitting.width + 14, height: fitting.height)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(timeInterval: visibleSeconds, target: self,
                                         selector: #selector(hideTimerFired), userInfo: nil, repeats: false)
    }

    func update(remaining: TimeInterval) {
        let seconds = max(0, Int(remaining.rounded(.up)))
        titleLabel.stringValue = L("Break in %d:%02d", seconds / 60, seconds % 60)
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

    @objc private func snoozeTapped(_ sender: NSButton) {
        close()
        onSnooze(sender.tag)
    }
}
