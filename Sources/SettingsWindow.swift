import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// The Settings window, in tabs: timing and general options, blink and posture nudges, when to pause
/// or hold breaks, and the schedule.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    /// The work interval changed, so the countdown should start over.
    var onWorkChanged: () -> Void = {}
    /// Anything else changed that the menu bar may show.
    var onChanged: () -> Void = {}
    /// The language changed; the window already rebuilt itself.
    var onLanguageChanged: () -> Void = {}
    /// A blink or posture nudge was turned on, off or changed, so they should start counting again.
    var onNudgesChanged: () -> Void = {}

    private var window: NSWindow?

    private enum Field: Int { case work, breakLength, longBreak, warn, idle, blink, posture }

    /// Presets shared with the menu's submenus.
    static let workPresets = [20, 30, 45, 60, 90].map { $0 * 60 }
    static let breakPresets = [2, 5, 10, 15].map { $0 * 60 }

    private static let options: [Field: [Int]] = [
        .work: workPresets,
        .breakLength: breakPresets,
        .longBreak: [0, 10, 15, 20, 30].map { $0 * 60 },
        .warn: [0, 30, 60, 120, 300],
        .idle: [0, 30, 60, 120, 300],
        .blink: [0, 10, 15, 20, 30].map { $0 * 60 },
        .posture: [0, 15, 30, 45, 60].map { $0 * 60 },
    ]
    /// Tag of each popup's last item, which asks for a custom value.
    private static let customTag = -1

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Ends any edit in progress, so a planned break's name typed just before closing is saved.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
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

    private enum Tab: Int { case general, wellness, smartPause, schedule }

    /// Builds the window's content in the current language, keeping the selected tab.
    private func fill(_ window: NSWindow) {
        let selected = (window.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex ?? 0
        activityCheckboxes = []
        focusAppList = nil
        plannedList = nil
        workHourControls = []
        longBreakEvery = nil

        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        for tab in [Tab.general, .wellness, .smartPause, .schedule] {
            let item = NSTabViewItem(viewController: page(tab))
            switch tab {
            case .general:
                item.label = L("General")
                item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
            case .wellness:
                item.label = L("Wellness")
                item.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
            case .smartPause:
                item.label = L("Smart Pause")
                item.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
            case .schedule:
                item.label = L("Schedule")
                item.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
            }
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = min(selected, tabs.tabViewItems.count - 1)
        window.contentViewController = tabs
        tabs.fitWindow(animated: false)
    }

    private func page(_ tab: Tab) -> NSViewController {
        let rows: [[NSView]]
        /// Extra room above some rows, to group them.
        var gaps: [Int: CGFloat] = [:]
        var header: NSView?
        switch tab {
        case .general:
            header = brandHeader()
            rows = [
                [label(L("Remind me every")), popup(.work)],
                [label(L("Break length")), popup(.breakLength)],
                [label(L("Long break")), popup(.longBreak)],
                [label(""), longBreakEveryPopup()],
                [label(""), hint(L("Every few breaks, one runs longer, so you can get up and walk around."))],
                [label(L("Warn me before breaks")), popup(.warn)],
                [label(L("Sounds")), soundsCheckbox()],
                [label(L("Volume")), volumeSlider()],
                [label(""), hint(L("A soft chime for the heads-up, the start of a break and its end."))],
                [label(L("Language")), languagePopup()],
                [label(""), launchAtLoginCheckbox()],
            ]
            gaps = [2: 10, 5: 10, 6: 14, 9: 14]
        case .wellness:
            rows = [
                [label(L("Blink and look away every")), popup(.blink)],
                [label(""), hint(L("Looking at a screen, you blink about half as often, which dries out your eyes."))],
                [label(L("Check my posture every")), popup(.posture)],
                [label(""), hint(L("A nudge to sit back, drop your shoulders and unclench your jaw."))],
                [label(""), hint(L("Nudges count only your working time and show for a few seconds under the menu bar icon. One that comes due just before a break is left to the break, and they wait whenever Smart Pause would hold a break."))],
            ]
            gaps = [2: 14, 4: 14]
        case .smartPause:
            let activities = Activity.allCases.enumerated().map { index, activity in
                [label(index == 0 ? L("Keep counting during") : ""), activityCheckbox(activity)]
            }
            rows = [
                [label(L("Pause when away after")), popup(.idle)],
                [label(""), hint(L("No keyboard, mouse or trackpad input for this long stops the countdown."))],
            ] + activities + [
                [label(""), hint(L("Calls are noticed by the microphone or camera being in use, videos by an app keeping the screen awake. Keep-awake apps count as a video."))],
                [label(L("Hold breaks")), holdCheckbox(L("During calls and meetings"), on: Settings.holdBreaksDuringCalls,
                                                       action: #selector(toggleHoldBreaks(_:)))],
                [label(""), holdCheckbox(L("While I'm typing or dragging"), on: Settings.holdBreaksWhileTyping,
                                         action: #selector(toggleHoldWhileTyping(_:)))],
                [label(""), holdCheckbox(L("While an app is in full screen"), on: Settings.holdBreaksInFullScreen,
                                         action: #selector(toggleHoldInFullScreen(_:)))],
                [label(L("Focus apps")), focusAppsView()],
                [label(""), hint(L("A break that comes due waits until the call ends or you leave the app. Typing holds it for up to a minute, until you pause."))],
            ]
            gaps = [2: 6, 2 + activities.count + 1: 14, rows.count - 2: 10]
        case .schedule:
            rows = [
                [label(L("Work hours")), holdCheckbox(L("Only remind me during work hours"), on: Settings.workHoursOn,
                                                      action: #selector(toggleWorkHours(_:)))],
                [label(L("Days")), workDaysControl()],
                [label(L("Hours")), workHoursControl()],
                [label(""), hint(L("Outside these hours Sway stays quiet. When they begin, a fresh countdown starts."))],
                [label(L("Planned breaks")), plannedBreaksView()],
                [label(""), hint(L("Each starts at its time with its own name and length, and gets a heads-up like other breaks. One whose time passes while you're away is skipped."))],
            ]
            gaps = [4: 14]
            for control in workHourControls { control.isEnabled = Settings.workHoursOn }
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for (row, gap) in gaps { grid.row(at: row).topPadding = gap }
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        var constraints = [
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
        ]
        if let header {
            container.addSubview(header)
            constraints += [
                header.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
                header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            ]
        } else {
            constraints.append(grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 24))
        }
        NSLayoutConstraint.activate(constraints)
        let controller = NSViewController()
        controller.view = container
        return controller
    }

    // MARK: Controls

    /// The cat with the app's name and tagline, above the settings.
    private func brandHeader() -> NSView {
        let name = NSTextField(labelWithString: "Sway")
        name.font = Typography.display(26, weight: .semibold)
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
        case .longBreak: Settings.longBreakSeconds
        case .blink: Settings.blinkSeconds
        case .posture: Settings.postureSeconds
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

    /// How often a break is a long one, e.g. "Every 4 breaks"; only used while long breaks are on.
    private var longBreakEvery: NSPopUpButton?

    private func longBreakEveryPopup() -> NSPopUpButton {
        let popup = NSPopUpButton()
        for count in 2...6 {
            popup.addItem(withTitle: L("Every %d breaks", count))
            popup.lastItem?.tag = count
        }
        popup.selectItem(withTag: Settings.longBreakEvery)
        popup.isEnabled = Settings.longBreakSeconds > 0
        popup.target = self
        popup.action = #selector(longBreakEveryChosen(_:))
        longBreakEvery = popup
        return popup
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

    private func holdCheckbox(_ title: String, on: Bool, action: Selector) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: self, action: action)
        checkbox.state = on ? .on : .off
        return checkbox
    }

    /// The apps that hold breaks while in front, each with a remove button, then an Add button.
    private var focusAppList: NSStackView?

    private func focusAppsView() -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        focusAppList = list
        reloadFocusApps()
        return list
    }

    private func reloadFocusApps() {
        guard let list = focusAppList else { return }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, id) in Settings.focusApps.enumerated() {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let icon = NSImageView(image: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let name = NSTextField(labelWithString: url.map { FileManager.default.displayName(atPath: $0.path) } ?? id)
            let remove = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: L("Remove"))!,
                                  target: self, action: #selector(removeFocusApp(_:)))
            remove.isBordered = false
            remove.contentTintColor = .secondaryLabelColor
            remove.tag = index
            let row = NSStackView(views: [icon, name, remove])
            row.spacing = 6
            list.addArrangedSubview(row)
        }
        let add = NSButton(title: L("Add App…"), target: self, action: #selector(addFocusApp))
        add.controlSize = .small
        list.addArrangedSubview(add)
        (window?.contentViewController as? SettingsTabs)?.fitWindow(animated: true)
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

    /// The days and hours pickers, which only apply while work hours are on.
    private var workHourControls: [NSControl] = []

    /// One toggle per weekday, starting on the calendar's first day of the week.
    private func workDaysControl() -> NSSegmentedControl {
        var calendar = Calendar.current
        calendar.locale = appLocale
        let days = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let control = NSSegmentedControl(labels: days.map { calendar.veryShortStandaloneWeekdaySymbols[$0 - 1] },
                                         trackingMode: .selectAny, target: self, action: #selector(workDaysChanged(_:)))
        for (index, day) in days.enumerated() {
            control.setTag(day, forSegment: index)
            control.setWidth(30, forSegment: index)
            control.setSelected(Settings.workDays.contains(day), forSegment: index)
            control.setToolTip(calendar.standaloneWeekdaySymbols[day - 1], forSegment: index)
        }
        workHourControls.append(control)
        return control
    }

    /// "9:00 to 18:00", as two time pickers.
    private func workHoursControl() -> NSView {
        let start = timePicker(minutes: Settings.workStart, action: #selector(workStartChanged(_:)))
        let end = timePicker(minutes: Settings.workEnd, action: #selector(workEndChanged(_:)))
        workHourControls += [start, end]
        let row = NSStackView(views: [start, NSTextField(labelWithString: L("to")), end])
        row.spacing = 8
        return row
    }

    private func timePicker(minutes: Int, action: Selector) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.locale = appLocale
        picker.dateValue = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        picker.target = self
        picker.action = action
        return picker
    }

    private static func minutes(of picker: NSDatePicker) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Planned breaks, one row each (name, time, length, remove), then an Add button.
    private var plannedList: NSStackView?
    private static let plannedLengths = [5, 10, 15, 20, 30, 45, 60, 90]

    private func plannedBreaksView() -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8
        plannedList = list
        reloadPlannedBreaks()
        return list
    }

    private func reloadPlannedBreaks() {
        guard let list = plannedList else { return }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, planned) in Settings.plannedBreaks.enumerated() {
            let name = NSTextField(string: planned.title)
            name.placeholderString = L("Name")
            name.widthAnchor.constraint(equalToConstant: 110).isActive = true
            name.cell?.sendsActionOnEndEditing = true
            name.target = self
            name.action = #selector(plannedNameChanged(_:))
            name.tag = index

            let time = timePicker(minutes: planned.start, action: #selector(plannedTimeChanged(_:)))
            time.tag = index

            let length = NSPopUpButton()
            for minutes in (Self.plannedLengths + [planned.length]).reduce(into: [Int](), { if !$0.contains($1) { $0.append($1) } }).sorted() {
                length.addItem(withTitle: Self.format(minutes * 60))
                length.lastItem?.tag = minutes
            }
            length.selectItem(withTag: planned.length)
            length.target = self
            length.action = #selector(plannedLengthChanged(_:))
            length.tag = index

            let remove = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: L("Remove"))!,
                                  target: self, action: #selector(removePlannedBreak(_:)))
            remove.isBordered = false
            remove.contentTintColor = .secondaryLabelColor
            remove.tag = index

            let row = NSStackView(views: [name, time, NSTextField(labelWithString: L("for")), length, remove])
            row.spacing = 6
            list.addArrangedSubview(row)
        }
        let add = NSButton(title: L("Add Break"), target: self, action: #selector(addPlannedBreak))
        add.controlSize = .small
        list.addArrangedSubview(add)
        (window?.contentViewController as? SettingsTabs)?.fitWindow(animated: true)
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
        case .longBreak: L("Long break length in minutes?")
        case .blink: L("Remind me to blink every how many minutes?")
        case .posture: L("Remind me about my posture every how many minutes?")
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
        case .longBreak:
            Settings.longBreakSeconds = seconds
            longBreakEvery?.isEnabled = seconds > 0
            onChanged()
        case .blink: Settings.blinkSeconds = seconds; onNudgesChanged()
        case .posture: Settings.postureSeconds = seconds; onNudgesChanged()
        case .warn: Settings.warnSeconds = seconds; onChanged()
        case .idle:
            Settings.idleSeconds = seconds
            // The activities only matter while away detection is on.
            for checkbox in activityCheckboxes { checkbox.isEnabled = seconds > 0 }
            onChanged()
        }
    }

    @objc private func longBreakEveryChosen(_ popup: NSPopUpButton) {
        Settings.longBreakEvery = popup.selectedTag()
        onChanged()
    }

    @objc private func toggleHoldBreaks(_ checkbox: NSButton) {
        Settings.holdBreaksDuringCalls = checkbox.state == .on
        onChanged()
    }

    @objc private func toggleWorkHours(_ checkbox: NSButton) {
        Settings.workHoursOn = checkbox.state == .on
        for control in workHourControls { control.isEnabled = Settings.workHoursOn }
        onChanged()
    }

    @objc private func workDaysChanged(_ control: NSSegmentedControl) {
        Settings.workDays = (0..<control.segmentCount).filter { control.isSelected(forSegment: $0) }
            .map { control.tag(forSegment: $0) }.sorted()
        onChanged()
    }

    @objc private func workStartChanged(_ picker: NSDatePicker) {
        Settings.workStart = Self.minutes(of: picker)
        onChanged()
    }

    @objc private func workEndChanged(_ picker: NSDatePicker) {
        Settings.workEnd = Self.minutes(of: picker)
        onChanged()
    }

    /// The first planned break suggests lunch; later ones an afternoon walk.
    @objc private func addPlannedBreak() {
        let first = Settings.plannedBreaks.isEmpty
        Settings.plannedBreaks.append(first ? PlannedBreak(title: L("Lunch"), start: 12 * 60 + 30, length: 60)
                                            : PlannedBreak(title: L("Walk"), start: 15 * 60 + 30, length: 15))
        reloadPlannedBreaks()
        onChanged()
    }

    @objc private func removePlannedBreak(_ sender: NSButton) {
        guard Settings.plannedBreaks.indices.contains(sender.tag) else { return }
        Settings.plannedBreaks.remove(at: sender.tag)
        reloadPlannedBreaks()
        onChanged()
    }

    @objc private func plannedNameChanged(_ field: NSTextField) {
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        editPlanned(field.tag) { $0.title = name.isEmpty ? L("Break") : name }
    }

    @objc private func plannedTimeChanged(_ picker: NSDatePicker) {
        editPlanned(picker.tag) { $0.start = Self.minutes(of: picker) }
    }

    @objc private func plannedLengthChanged(_ popup: NSPopUpButton) {
        editPlanned(popup.tag) { $0.length = popup.selectedTag() }
    }

    private func editPlanned(_ index: Int, _ change: (inout PlannedBreak) -> Void) {
        var all = Settings.plannedBreaks
        guard all.indices.contains(index) else { return }
        change(&all[index])
        Settings.plannedBreaks = all
        onChanged()
    }

    @objc private func toggleHoldWhileTyping(_ checkbox: NSButton) {
        Settings.holdBreaksWhileTyping = checkbox.state == .on
    }

    @objc private func toggleHoldInFullScreen(_ checkbox: NSButton) {
        Settings.holdBreaksInFullScreen = checkbox.state == .on
    }

    @objc private func addFocusApp() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Add")
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK else { return }
                let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
                Settings.focusApps += ids.filter { !Settings.focusApps.contains($0) }
                self?.reloadFocusApps()
            }
        }
    }

    @objc private func removeFocusApp(_ sender: NSButton) {
        guard Settings.focusApps.indices.contains(sender.tag) else { return }
        Settings.focusApps.remove(at: sender.tag)
        reloadFocusApps()
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

/// Toolbar-style tabs that resize the window to fit each tab, keeping its top edge in place.
private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: true)
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window, let content = tabViewItems[selectedTabViewItemIndex].viewController?.view else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}
