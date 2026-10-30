import AppKit

/// Small popover under the menu bar item that says how long you were away.
@MainActor
final class AwayNotice: NSObject {
    private let popover = NSPopover()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    /// The popover hides itself after this long so it never lingers.
    private let visibleSeconds: TimeInterval = 8

    var isShown: Bool { popover.isShown }

    override init() {
        super.init()

        let mark = NSImage(size: NSSize(width: 28, height: 28), flipped: false) { rect in
            SwayMark.draw(in: rect.insetBy(dx: 1, dy: 1), lineScale: 1.3)
            return true
        }
        let icon = NSImageView(image: mark)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let stack = NSStackView(views: [icon, text])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        let controller = NSViewController()
        controller.view = stack
        popover.contentViewController = controller
        popover.behavior = .semitransient
        popover.animates = true
    }

    /// `countedAsBreak` says the time away was long enough to start a fresh cycle.
    func show(relativeTo button: NSStatusBarButton, away: TimeInterval, countedAsBreak: Bool) {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = away >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .full
        let duration = formatter.string(from: max(60, away)) ?? ""
        titleLabel.stringValue = L("You were away for %@", duration)
        subtitleLabel.stringValue = countedAsBreak
            ? L("That counts as a break, so the timer started over.")
            : L("The countdown waited for you.")

        if let content = popover.contentViewController?.view {
            content.layoutSubtreeIfNeeded()
            popover.contentSize = content.fittingSize
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(timeInterval: visibleSeconds, target: self,
                                         selector: #selector(hideTimerFired), userInfo: nil, repeats: false)
    }

    func close() {
        hideTimer?.invalidate()
        hideTimer = nil
        if popover.isShown { popover.close() }
    }

    @objc private func hideTimerFired() { close() }
}
