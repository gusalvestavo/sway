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

        let icon = MascotView(.happy, height: 44)

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

    /// `countedAsBreak` says the Mac slept or locked meanwhile, so a fresh cycle started.
    func show(relativeTo button: NSStatusBarButton, away: TimeInterval, countedAsBreak: Bool) {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = away >= 3600 ? [.hour, .minute] : away >= 60 ? [.minute] : [.second]
        formatter.unitsStyle = .full
        var calendar = Calendar.current
        calendar.locale = appLocale
        formatter.calendar = calendar
        let duration = formatter.string(from: away) ?? ""
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
