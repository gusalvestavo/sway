import AppKit

/// Sway's cat, in the poses from docs/brand/mascot-sheet.webp (Resources/Mascot/<pose>.png).
enum Mascot: String {
    case focus, getReady = "get-ready", napping, cheering, sitting, relaxed, happy, sleeping
    case curious, thinking, excited, stretching

    @MainActor private static var cache: [Mascot: NSImage] = [:]

    @MainActor var image: NSImage {
        if let image = Self.cache[self] { return image }
        let url = Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Mascot")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        Self.cache[self] = image
        return image
    }
}

/// Shows a mascot pose at a fixed height; the width follows the pose's proportions.
final class MascotView: NSImageView {
    private let height: CGFloat
    private var widthConstraint: NSLayoutConstraint!

    var pose: Mascot {
        didSet { if pose != oldValue { apply() } }
    }

    init(_ pose: Mascot, height: CGFloat) {
        self.pose = pose
        self.height = height
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: height)
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height), widthConstraint])
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func apply() {
        let image = pose.image
        self.image = image
        widthConstraint.constant = image.size.height > 0 ? height * image.size.width / image.size.height : height
    }
}
