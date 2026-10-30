import AppKit

/// Cheerful lines for the first return of a new day; keys are the English text.
private let motivationalMessages = [
    "A brand-new day. Let's make it a great one!",
    "Fresh start, fresh ideas. You've got this!",
    "Today is full of possibilities. Go get them!",
    "Small steps add up. Let's take the first one!",
    "You showed up, and that's the hardest part. Let's go!",
    "Big things are built one focused hour at a time.",
    "New day, new energy. Let's do something amazing!",
    "You're capable of more than you think. Show today!",
    "Today's a great day to make progress. Ready, set, go!",
    "Your best work is still ahead of you. Let's start!",
]

/// Popover under the menu bar item that welcomes you back on a new day.
@MainActor
final class Greeting: NSObject {
    private let popover = NSPopover()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let goButton = NSButton(title: "", target: nil, action: nil)
    private var hideTimer: Timer?

    /// The popover hides itself after this long so it never lingers.
    private let visibleSeconds: TimeInterval = 20

    override init() {
        super.init()

        let cat = MascotView(.excited, height: 84)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.preferredMaxLayoutWidth = 240
        countdownLabel.font = .systemFont(ofSize: 11)
        countdownLabel.textColor = .secondaryLabelColor

        goButton.target = self
        goButton.action = #selector(goTapped)
        goButton.controlSize = .regular
        goButton.useGlass(tint: SwayMark.sage)

        let text = NSStackView(views: [titleLabel, messageLabel, countdownLabel, goButton])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        text.setCustomSpacing(10, after: countdownLabel)

        let stack = NSStackView(views: [cat, text])
        stack.alignment = .centerY
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Explicit margins: a stack view as the popover's root view loses its top and bottom insets.
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
        ])

        let controller = NSViewController()
        controller.view = container
        popover.contentViewController = controller
        popover.behavior = .semitransient
        popover.animates = true
    }

    /// `nextBreak` is the new countdown's length, already formatted (e.g. "45 min").
    func show(relativeTo button: NSStatusBarButton, nextBreak: String) {
        // Built on each show so a language change since launch is picked up.
        titleLabel.stringValue = Self.salutation()
        messageLabel.stringValue = L(motivationalMessages.randomElement()!)
        countdownLabel.stringValue = L("Your countdown has started: next break in %@.", nextBreak)
        goButton.title = L("Let's go!")

        if let content = popover.contentViewController?.view {
            content.layoutSubtreeIfNeeded()
            popover.contentSize = content.fittingSize
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(timeInterval: visibleSeconds, target: self,
                                         selector: #selector(close), userInfo: nil, repeats: false)
    }

    @objc func close() {
        hideTimer?.invalidate()
        hideTimer = nil
        if popover.isShown { popover.close() }
    }

    @objc private func goTapped() { close() }

    /// "Good morning, Ana!" by time of day, with the first name of the Mac's user when there is one.
    private static func salutation() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        switch (hour, name.isEmpty) {
        case (5..<12, false): return L("Good morning, %@!", name)
        case (5..<12, true): return L("Good morning!")
        case (12..<18, false): return L("Good afternoon, %@!", name)
        case (12..<18, true): return L("Good afternoon!")
        case (_, false): return L("Good evening, %@!", name)
        case (_, true): return L("Good evening!")
        }
    }
}
