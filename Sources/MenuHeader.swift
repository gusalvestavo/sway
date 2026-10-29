import AppKit

struct HeaderState: Equatable {
    var caption: String
    var value: String
    var showsAddTime: Bool
}

/// Top section of the menu: the current state in large type, plus buttons to add time.
final class MenuHeaderView: NSView {
    static let addTimeOptions = [1, 5, 15]

    var onAddTime: (Int) -> Void = { _ in }

    private let caption = NSTextField(labelWithString: "")
    private let value = RollingTextView(font: .monospacedDigitSystemFont(ofSize: 34, weight: .light))
    private let addRow: NSStackView
    private let stack = NSStackView()
    private let width: CGFloat = 250

    init(state: HeaderState) {
        let buttons = Self.addTimeOptions.map { minutes in
            let button = NSButton(title: L("+%d min", minutes), target: nil, action: nil)
            button.tag = minutes
            button.controlSize = .small
            button.useGlass()
            return button
        }
        addRow = NSStackView(views: buttons)
        addRow.spacing = 6

        super.init(frame: .zero)
        autoresizingMask = [.width]
        for button in buttons {
            button.target = self
            button.action = #selector(addTapped(_:))
        }

        caption.font = .systemFont(ofSize: 12, weight: .medium)
        caption.textColor = .secondaryLabelColor

        [caption, value, addRow].forEach(stack.addArrangedSubview)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        // The value carries its own 8px padding (its clipping area), so it needs little extra spacing.
        stack.setCustomSpacing(0, after: caption)
        stack.setCustomSpacing(2, after: value)
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
        ])

        update(state, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ state: HeaderState, animated: Bool) {
        caption.stringValue = state.caption
        value.setText(state.value, animated: animated)
        let hiddenChanged = addRow.isHidden == state.showsAddTime
        addRow.isHidden = !state.showsAddTime
        if hiddenChanged || frame.height == 0 {
            setFrameSize(NSSize(width: max(frame.width, width), height: stack.fittingSize.height))
        }
    }

    @objc private func addTapped(_ sender: NSButton) { onAddTime(sender.tag) }
}

/// Text where each digit rolls in when it changes, like a mechanical counter.
/// Rolling digits are clipped to this view, which pads the text by 8px above and below.
final class RollingTextView: NSStackView {
    private let font: NSFont
    private var labels: [NSTextField] = []

    init(font: NSFont) {
        self.font = font
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 0
        edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        wantsLayer = true
        layer?.masksToBounds = true
        if #available(macOS 14, *) { clipsToBounds = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setText(_ text: String, animated: Bool) {
        // Clocks get one cell per character so only changed digits roll; words stay whole to keep kerning.
        let cells = text.contains(where: \.isNumber) ? text.map(String.init) : [text]
        guard cells.count == labels.count else {
            labels.forEach { $0.removeFromSuperview() }
            labels = cells.map(makeLabel)
            labels.forEach(addArrangedSubview)
            return
        }
        for (label, cell) in zip(labels, cells) where label.stringValue != cell {
            if animated, let layer = label.layer {
                let roll = CATransition()
                roll.type = .push
                roll.subtype = .fromTop
                roll.duration = 0.35
                roll.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(roll, forKey: "roll")
            }
            label.stringValue = cell
        }
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.wantsLayer = true
        return label
    }
}
