import AppKit
import ServiceManagement

/// The Settings window: timing, sounds, language and Launch at Login.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    /// The work interval changed, so the countdown should start over.
    var onWorkChanged: () -> Void = {}
    /// Anything else changed that the menu bar may show.
    var onChanged: () -> Void = {}
    /// The language changed; the window already rebuilt itself.
    var onLanguageChanged: () -> Void = {}

    private var window: NSWindow?

    private enum Field: Int { case work, breakLength, warn, idle }

    /// Presets shared with the menu's submenus.
    static let workPresets = [20, 30, 45, 60, 90].map { $0 * 60 }
    static let breakPresets = [2, 5, 10, 15].map { $0 * 60 }

    private static let options: [Field: [Int]] = [
        .work: workPresets,
        .breakLength: breakPresets,
        .warn: [0, 30, 60, 120, 300],
        .idle: [0, 30, 60, 120, 300],
    ]
    /// Tag of each popup's last item, which asks for a custom value.
    private static let customTag = -1

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Shows values changed elsewhere, such as from the menu.
    func refresh() {
        if let window { fill(window) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.delegate = self
        fill(window)
        window.center()
        return window
    }

    /// Builds the window's content in the current language.
    private func fill(_ window: NSWindow) {
        window.title = L("Settings")
        activityCheckboxes = []

        let rows: [[NSView]] = [
            [label(L("Remind me every")), popup(.work)],
            [label(L("Break length")), popup(.breakLength)],
            [label(L("Warn me before breaks")), popup(.warn)],
            [label(L("Pause when away after")), popup(.idle)],
            [label(""), hint(L("No keyboard, mouse or trackpad input for this long stops the countdown."))],
        ] + Activity.allCases.enumerated().map { index, activity in
            [label(index == 0 ? L("Keep counting during") : ""), activityCheckbox(activity)]
        } + [
            [label(""), hint(L("Calls are noticed by the microphone or camera being in use, videos by an app keeping the screen awake. Keep-awake apps count as a video."))],
            [label(L("During calls")), holdBreaksCheckbox()],
            [label(""), hint(L("A break that comes due during a call waits until it ends."))],
            [label(L("Sounds")), soundsCheckbox()],
            [label(L("Volume")), volumeSlider()],
            [label(""), hint(L("A soft chime for the heads-up, the start of a break and its end."))],
            [label(L("Language")), languagePopup()],
            [label(""), launchAtLoginCheckbox()],
        ]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        // Extra room before the activities, the calls section, the sounds and the general rows.
        grid.row(at: 5).topPadding = 6
        grid.row(at: rows.count - 7).topPadding = 14
        grid.row(at: rows.count - 5).topPadding = 14
        grid.row(at: rows.count - 2).topPadding = 14

        let container = NSView()
        let header = brandHeader()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
        ])
        window.contentView = container
        window.setContentSize(container.fittingSize)
    }

    // MARK: Controls

    /// The cat with the app's name and tagline, above the settings.
    private func brandHeader() -> NSView {
        let name = NSTextField(labelWithString: "Sway")
        name.font = .systemFont(ofSize: 26, weight: .semibold)
        // Sage reads too dark on a dark window, so dark mode uses the lighter leaf green.
        name.textColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? SwayMark.leaf : SwayMark.sage
        }
        let tagline = NSTextField(labelWithString: L("Find your flow."))
        tagline.font = .systemFont(ofSize: 13)
        tagline.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, tagline])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0

        let header = NSStackView(views: [MascotView(.sitting, height: 76), text])
        header.spacing = 14
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text.isEmpty ? "" : text + ":")
    }

    private func hint(_ text: String) -> NSTextField {
        let hint = NSTextField(wrappingLabelWithString: text)
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 260
        return hint
    }

    private func value(_ field: Field) -> Int {
        switch field {
        case .work: Settings.workSeconds
        case .breakLength: Settings.breakSeconds
        case .warn: Settings.warnSeconds
        case .idle: Settings.idleSeconds
        }
    }

    private func popup(_ field: Field) -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.tag = field.rawValue
        popup.target = self
        popup.action = #selector(durationChosen(_:))
        reload(popup)
        return popup
    }

    /// Lists the presets, plus the current value when it's a custom one, then "Custom…".
    private func reload(_ popup: NSPopUpButton) {
        guard let field = Field(rawValue: popup.tag) else { return }
        let current = value(field)
        let choices = (Self.options[field]! + [current]).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
        popup.removeAllItems()
        for seconds in choices.sorted() {
            popup.addItem(withTitle: Self.format(seconds))
            popup.lastItem?.tag = seconds
        }
        popup.menu?.addItem(.separator())
        popup.addItem(withTitle: L("Custom…"))
        popup.lastItem?.tag = Self.customTag
        popup.selectItem(withTag: current)
    }

    private func languagePopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        popup.addItem(withTitle: L("Same as the system"))
        popup.menu?.addItem(.separator())
        for language in supportedLanguages {
            popup.addItem(withTitle: language.name)
            popup.lastItem?.representedObject = language.code
        }
        if let code = Settings.language, let index = supportedLanguages.firstIndex(where: { $0.code == code }) {
            popup.selectItem(at: index + 2)
        } else {
            popup.selectItem(at: 0)
        }
        popup.target = self
        popup.action = #selector(languageChosen(_:))
        return popup
    }

    private var activityCheckboxes: [NSButton] = []

    private func activityCheckbox(_ activity: Activity) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: activity.title, target: self, action: #selector(toggleActivity(_:)))
        checkbox.tag = Activity.allCases.firstIndex(of: activity)!
        checkbox.state = Settings.keepsCounting(activity) ? .on : .off
        checkbox.isEnabled = Settings.idleSeconds > 0
        activityCheckboxes.append(checkbox)
        return checkbox
    }

    private func holdBreaksCheckbox() -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: L("Hold breaks until the call ends"), target: self,
                                action: #selector(toggleHoldBreaks(_:)))
        checkbox.state = Settings.holdBreaksDuringCalls ? .on : .off
        return checkbox
    }

    private var volume: NSSlider?

    private func soundsCheckbox() -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: L("Play sounds for breaks"), target: self,
                                action: #selector(toggleSounds(_:)))
        checkbox.state = Settings.playSounds ? .on : .off
        return checkbox
    }

    /// A slider between a quiet and a loud speaker; letting go plays the heads-up chime at the new volume.
    private func volumeSlider() -> NSView {
        let slider = NSSlider(value: Settings.soundVolume, minValue: 0.05, maxValue: 1, target: self,
                              action: #selector(volumeChanged(_:)))
        slider.isContinuous = false
        slider.isEnabled = Settings.playSounds
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        volume = slider
        let speaker = { (name: String) in
            let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)!)
            view.contentTintColor = .secondaryLabelColor
            return view
        }
        let row = NSStackView(views: [speaker("speaker.fill"), slider, speaker("speaker.wave.3.fill")])
        row.spacing = 6
        return row
    }

    private func launchAtLoginCheckbox() -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: L("Launch at Login"), target: self,
                                action: #selector(toggleLaunchAtLogin(_:)))
        checkbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        return checkbox
    }

    // MARK: Actions

    @objc private func durationChosen(_ popup: NSPopUpButton) {
        guard let field = Field(rawValue: popup.tag), let item = popup.selectedItem else { return }
        if item.tag == Self.customTag {
            // Put the previous choice back until a custom value is saved.
            popup.selectItem(withTag: value(field))
            askCustom(field, popup: popup)
        } else {
            save(item.tag, to: field)
        }
    }

    private func askCustom(_ field: Field, popup: NSPopUpButton) {
        guard let window else { return }
        let question = switch field {
        case .work: L("Remind me every how many minutes?")
        case .breakLength: L("Break length in minutes?")
        case .warn: L("Warn me how many minutes before a break?")
        case .idle: L("Pause after how many minutes away?")
        }
        let alert = NSAlert()
        alert.messageText = question
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        input.stringValue = String(max(1, value(field) / 60))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn,
                      let minutes = Int(input.stringValue.trimmingCharacters(in: .whitespaces)),
                      (1...600).contains(minutes) else { return }
                self?.save(minutes * 60, to: field)
                self?.reload(popup)
            }
        }
    }

    private func save(_ seconds: Int, to field: Field) {
        switch field {
        case .work:
            Settings.workSeconds = seconds
            onWorkChanged()
        case .breakLength: Settings.breakSeconds = seconds; onChanged()
        case .warn: Settings.warnSeconds = seconds; onChanged()
        case .idle:
            Settings.idleSeconds = seconds
            // The activities only matter while away detection is on.
            for checkbox in activityCheckboxes { checkbox.isEnabled = seconds > 0 }
            onChanged()
        }
    }

    @objc private func toggleHoldBreaks(_ checkbox: NSButton) {
        Settings.holdBreaksDuringCalls = checkbox.state == .on
        onChanged()
    }

    @objc private func toggleSounds(_ checkbox: NSButton) {
        Settings.playSounds = checkbox.state == .on
        volume?.isEnabled = Settings.playSounds
    }

    @objc private func volumeChanged(_ slider: NSSlider) {
        Settings.soundVolume = slider.doubleValue
        Sound.headsUp.preview()
    }

    @objc private func toggleActivity(_ checkbox: NSButton) {
        Settings.setKeepsCounting(Activity.allCases[checkbox.tag], checkbox.state == .on)
    }

    @objc private func languageChosen(_ popup: NSPopUpButton) {
        let code = popup.selectedItem?.representedObject as? String
        guard code != Settings.language else { return }
        Settings.language = code
        applyLanguage(code)
        onLanguageChanged()
        // Rebuild after this action returns, since the popup sending it is part of the old content.
        DispatchQueue.main.async { [weak self] in
            if let window = self?.window { self?.fill(window) }
        }
    }

    @objc private func toggleLaunchAtLogin(_ checkbox: NSButton) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Couldn't change Launch at Login")
            alert.informativeText = error.localizedDescription + "\n\n" + L("Move Sway to your Applications folder and try again.")
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
        // macOS may ask you to approve the login item in System Settings first.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        checkbox.state = service.status == .enabled ? .on : .off
    }

    /// `0` reads as Off; under a minute in seconds, otherwise minutes.
    static func format(_ seconds: Int) -> String {
        switch seconds {
        case 0: L("Off")
        case ..<60: L("%d sec", seconds)
        default: L("%d min", seconds / 60)
        }
    }
}
