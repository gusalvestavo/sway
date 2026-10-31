import AppKit

/// Small reminders between breaks: to blink and look away, or to check your posture.
enum Nudge: CaseIterable {
    case blink, posture

    /// How often it comes; 0 is off.
    var seconds: Int {
        switch self {
        case .blink: Settings.blinkSeconds
        case .posture: Settings.postureSeconds
        }
    }

    fileprivate var pose: Mascot { self == .blink ? .curious : .sitting }

    fileprivate var title: String { self == .blink ? L("Blink slowly a few times") : L("Check your posture") }

    /// A few wordings, picked at random so it doesn't read the same every time.
    fileprivate var tips: [String] {
        switch self {
        case .blink: [L("Then look at something far away for 20 seconds."),
                      L("Let your eyes rest on something across the room.")]
        case .posture: [L("Sit back, drop your shoulders and unclench your jaw."),
                        L("Feet flat on the floor, screen at eye level."),
                        L("Roll your shoulders and sway a little.")]
        }
    }
}

/// Small popover under the menu bar item with a blink or posture nudge.
@MainActor
final class NudgeNotice: NSObject {
    private let popover = NSPopover()
    private let mascot = MascotView(.curious, height: 44)
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    /// Long enough to read, short enough not to need dismissing.
    private let visibleSeconds: TimeInterval = 7

    var isShown: Bool { popover.isShown }

    override init() {
        super.init()

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let stack = NSStackView(views: [mascot, text])
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        let controller = NSViewController()
        controller.view = stack
        popover.contentViewController = controller
        popover.behavior = .semitransient
        popover.animates = true
    }

    func show(_ nudge: Nudge, relativeTo button: NSStatusBarButton) {
        mascot.pose = nudge.pose
        titleLabel.stringValue = nudge.title
        subtitleLabel.stringValue = nudge.tips.randomElement()!
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
