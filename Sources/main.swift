import AppKit
import ServiceManagement

// MARK: - Settings

enum Settings {
    private static let defaults = UserDefaults.standard

    static var workSeconds: Int {
        get { defaults.object(forKey: "workSeconds") as? Int ?? 30 * 60 }
        set { defaults.set(newValue, forKey: "workSeconds") }
    }

    static var breakSeconds: Int {
        get { defaults.object(forKey: "breakSeconds") as? Int ?? 5 * 60 }
        set { defaults.set(newValue, forKey: "breakSeconds") }
    }

    /// How long before a break the warning popover appears; 0 turns it off.
    static var warnSeconds: Int {
        get { defaults.object(forKey: "warnSeconds") as? Int ?? 60 }
        set { defaults.set(newValue, forKey: "warnSeconds") }
    }
}

/// `--interval-seconds N`, `--break-seconds N` and `--warn-seconds N` override the settings
/// for this run only (handy for testing).
func argument(_ name: String) -> Int? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return Int(args[i + 1])
}

let intervalOverride = argument("--interval-seconds")
let breakOverride = argument("--break-seconds")
let warnOverride = argument("--warn-seconds")

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    enum Phase { case working, onBreak, breakOver, paused }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let overlay = BreakOverlay()
    private let warning = BreakWarning()
    private var timer: Timer?
    private var phase: Phase = .working
    private var deadline = Date()
    private var pausedRemaining: TimeInterval = 0
    private var warnedThisCycle = false
    /// The menu's header while the menu is open, so ticks can keep it live.
    private weak var header: MenuHeaderView?

    private var workSeconds: Int { intervalOverride ?? Settings.workSeconds }
    private var breakSeconds: Int { breakOverride ?? Settings.breakSeconds }
    private var warnSeconds: Int { warnOverride ?? Settings.warnSeconds }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.onEnd = { [unowned self] in startWork() }
        overlay.onPostpone = { [unowned self] minutes in startWork(after: minutes * 60) }
        warning.onStartNow = { [unowned self] in startBreak() }
        warning.onPostpone = { [unowned self] in startWork(after: 5 * 60) }
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        startWork()

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // After sleep or a locked screen you were most likely away, so that counts as a break.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(userReturned), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(userReturned),
            name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: Timer

    private func startWork(after seconds: Int? = nil) {
        overlay.close()
        warning.close()
        phase = .working
        let cycle = seconds ?? workSeconds
        deadline = Date().addingTimeInterval(TimeInterval(cycle))
        // A cycle shorter than the warning window (e.g. a 1-minute postpone) gets no warning.
        warnedThisCycle = cycle <= warnSeconds
        updateDisplay()
    }

    private func startBreak() {
        warning.close()
        phase = .onBreak
        deadline = Date().addingTimeInterval(TimeInterval(breakSeconds))
        overlay.show(duration: TimeInterval(breakSeconds))
        updateDisplay()
    }

    private func tick() {
        switch phase {
        case .working:
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                startBreak()
                return
            }
            if !warnedThisCycle, warnSeconds > 0, remaining <= TimeInterval(warnSeconds),
               let button = statusItem.button {
                warnedThisCycle = true
                warning.show(relativeTo: button, remaining: remaining)
            } else if warning.isShown {
                warning.update(remaining: remaining)
            }
            updateDisplay()
        case .onBreak:
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                // Keep the overlay up until you come back and click "Back to work".
                phase = .breakOver
                overlay.showFinished()
                updateDisplay()
            } else {
                overlay.update(remaining: remaining)
                updateDisplay()
            }
        case .breakOver, .paused:
            break
        }
    }

    @objc private func userReturned() {
        if phase == .working { startWork() }
    }

    // MARK: Menu

    private var remainingSeconds: Int { max(0, Int(deadline.timeIntervalSinceNow.rounded(.up))) }

    private func updateDisplay() {
        let title: String
        switch phase {
        case .working: title = short(remainingSeconds)
        case .onBreak: title = "Break \(short(remainingSeconds))"
        case .breakOver: title = "Break done"
        case .paused: title = "Paused \(short(Int(pausedRemaining)))"
        }
        statusItem.button?.title = " " + title
        let image = phase == .paused ? SwayMark.pausedMenuBarImage : SwayMark.menuBarImage
        if statusItem.button?.image !== image { statusItem.button?.image = image }
        header?.update(headerState, animated: true)
    }

    private var headerState: HeaderState {
        switch phase {
        case .working:
            HeaderState(caption: "Next break in", value: clock(remainingSeconds), showsAddTime: true)
        case .onBreak:
            HeaderState(caption: "On a break", value: clock(remainingSeconds), showsAddTime: false)
        case .breakOver:
            HeaderState(caption: "Break's over", value: "Welcome back", showsAddTime: false)
        case .paused:
            HeaderState(caption: "\(clock(Int(pausedRemaining))) left", value: "Paused", showsAddTime: true)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = MenuHeaderView(state: headerState)
        header.onAddTime = { [unowned self] minutes in addTime(minutes: minutes) }
        let headerItem = NSMenuItem()
        headerItem.view = header
        menu.addItem(headerItem)
        menu.addItem(.separator())
        self.header = header

        switch phase {
        case .onBreak: menu.addItem(item("End break now", #selector(endBreak)))
        case .breakOver: menu.addItem(item("Back to work", #selector(endBreak)))
        case .working, .paused: menu.addItem(item("Take a break now", #selector(breakNow)))
        }
        menu.addItem(item(phase == .paused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(item("Restart timer", #selector(restart)))
        menu.addItem(.separator())

        menu.addItem(submenu(title: "Remind me every", options: [20, 30, 45, 60, 90].map { $0 * 60 },
                             current: Settings.workSeconds, action: #selector(setWork(_:)),
                             customAction: #selector(customWork)))
        menu.addItem(submenu(title: "Break length", options: [2, 5, 10, 15].map { $0 * 60 },
                             current: Settings.breakSeconds, action: #selector(setBreak(_:)),
                             customAction: #selector(customBreak)))
        menu.addItem(submenu(title: "Warn me before breaks", options: [0, 30, 60, 120, 300],
                             current: Settings.warnSeconds, action: #selector(setWarn(_:)),
                             customAction: #selector(customWarn)))
        if intervalOverride != nil || breakOverride != nil || warnOverride != nil {
            let note = NSMenuItem(title: "Test mode: \(workSeconds)s work, \(breakSeconds)s break, \(warnSeconds)s warning",
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        switch SMAppService.mainApp.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed
        default: login.state = .off
        }
        menu.addItem(login)
        menu.addItem(item("Quit Sway", #selector(quit), key: "q"))
    }

    func menuDidClose(_ menu: NSMenu) {
        header = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenu(title: String, options: [Int], current: Int,
                         action: Selector, customAction: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(format(current))", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for seconds in options {
            let option = item(format(seconds), action)
            option.tag = seconds
            option.state = seconds == current ? .on : .off
            sub.addItem(option)
        }
        sub.addItem(.separator())
        sub.addItem(item("Custom…", customAction))
        parent.submenu = sub
        return parent
    }

    // MARK: Actions

    private func addTime(minutes: Int) {
        let extra = TimeInterval(minutes * 60)
        switch phase {
        case .working:
            deadline += extra
            // Re-arm the warning if the extra time moved the break out of the warning window.
            if deadline.timeIntervalSinceNow > TimeInterval(warnSeconds) {
                warnedThisCycle = false
                warning.close()
            }
        case .paused:
            pausedRemaining += extra
        case .onBreak, .breakOver:
            return
        }
        statusItem.menu?.cancelTracking()
        updateDisplay()
    }

    @objc private func breakNow() { startBreak() }
    @objc private func endBreak() { startWork() }
    @objc private func restart() { startWork() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func togglePause() {
        if phase == .paused {
            phase = .working
            deadline = Date().addingTimeInterval(pausedRemaining)
        } else {
            warning.close()
            pausedRemaining = max(0, deadline.timeIntervalSinceNow)
            if phase == .onBreak || phase == .breakOver {
                overlay.close()
                pausedRemaining = TimeInterval(workSeconds)
            }
            phase = .paused
        }
        updateDisplay()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove Sway to your Applications folder and try again."
            alert.runModal()
        }
        // macOS may ask you to approve the login item in System Settings first.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        updateDisplay()
    }

    @objc private func setWork(_ sender: NSMenuItem) {
        Settings.workSeconds = sender.tag
        startWork()
    }

    @objc private func setBreak(_ sender: NSMenuItem) {
        Settings.breakSeconds = sender.tag
        updateDisplay()
    }

    @objc private func setWarn(_ sender: NSMenuItem) {
        Settings.warnSeconds = sender.tag
        updateDisplay()
    }

    @objc private func customWarn() {
        if let minutes = askMinutes("Warn me how many minutes before a break?", current: Settings.warnSeconds / 60) {
            Settings.warnSeconds = minutes * 60
            updateDisplay()
        }
    }

    @objc private func customWork() {
        if let minutes = askMinutes("Remind me every how many minutes?", current: Settings.workSeconds / 60) {
            Settings.workSeconds = minutes * 60
            startWork()
        }
    }

    @objc private func customBreak() {
        if let minutes = askMinutes("Break length in minutes?", current: Settings.breakSeconds / 60) {
            Settings.breakSeconds = minutes * 60
            updateDisplay()
        }
    }

    private func askMinutes(_ question: String, current: Int) -> Int? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = question
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = String(current)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let minutes = Int(field.stringValue.trimmingCharacters(in: .whitespaces)),
              (1...600).contains(minutes) else { return nil }
        return minutes
    }

    // MARK: Formatting

    /// Countdown with seconds for the menu header, e.g. `1:05:09` or `24:13`.
    private func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Compact menu bar time, rounded up to the minute, e.g. `1h20m` or `40m`.
    private func short(_ seconds: Int) -> String {
        let minutes = (seconds + 59) / 60
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    private func format(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Off"
        case ..<60: "\(seconds) sec"
        default: "\(seconds / 60) min"
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
