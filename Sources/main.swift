import AppKit

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

    /// How long without input before the countdown stops; 0 turns it off.
    static var idleSeconds: Int {
        get { defaults.object(forKey: "idleSeconds") as? Int ?? 30 }
        set { defaults.set(newValue, forKey: "idleSeconds") }
    }

    /// Whether `activity` keeps the countdown running while there's no input.
    static func keepsCounting(_ activity: Activity) -> Bool {
        defaults.object(forKey: "keepCounting." + activity.rawValue) as? Bool ?? activity.enabledByDefault
    }

    static func setKeepsCounting(_ activity: Activity, _ on: Bool) {
        defaults.set(on, forKey: "keepCounting." + activity.rawValue)
    }

    /// Whether a break that comes due during a call waits until the call ends.
    static var holdBreaksDuringCalls: Bool {
        get { defaults.object(forKey: "holdBreaksDuringCalls") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "holdBreaksDuringCalls") }
    }

    /// Chimes for the heads-up, the start of a break and its end.
    static var playSounds: Bool {
        get { defaults.object(forKey: "playSounds") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "playSounds") }
    }

    /// From 0 to 1.
    static var soundVolume: Double {
        get { defaults.object(forKey: "soundVolume") as? Double ?? 0.7 }
        set { defaults.set(newValue, forKey: "soundVolume") }
    }

    /// The welcome window was shown (and finished or closed).
    static var welcomed: Bool {
        get { defaults.bool(forKey: "welcomed") }
        set { defaults.set(newValue, forKey: "welcomed") }
    }

    /// Nothing saved yet, so this is a new install rather than an update.
    static var isFirstLaunch: Bool {
        !welcomed && defaults.object(forKey: "lastActive") == nil && defaults.object(forKey: "workSeconds") == nil
    }

    /// When you last used the Mac, so a launch the next morning still greets you.
    static var lastActive: Date? {
        get { defaults.object(forKey: "lastActive") as? Date }
        set { defaults.set(newValue, forKey: "lastActive") }
    }

    /// The app's language as an .lproj code; nil follows the Mac's language.
    static var language: String? {
        get { defaults.string(forKey: "language") }
        set { defaults.set(newValue, forKey: "language") }
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
let idleOverride = argument("--idle-seconds")

/// Seconds since the last keyboard, mouse or trackpad event in this login session.
/// Needs no permission, unlike watching the events themselves.
func secondsSinceLastInput() -> TimeInterval {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// `away`: no input for a while, so the work countdown is frozen until you're back.
    enum Phase { case working, onBreak, breakOver, paused, away }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let overlay = BreakOverlay()
    private var warning = BreakWarning()
    private let settings = SettingsWindow()
    private let awayNotice = AwayNotice()
    private let greeting = Greeting()
    private var welcome: Welcome?
    private var timer: Timer?
    private var phase: Phase = .working
    private var deadline = Date()
    /// Time left on the countdown while paused or away.
    private var pausedRemaining: TimeInterval = 0
    /// When the last input happened before going away.
    private var awaySince = Date()
    /// When the current work countdown started (or resumed).
    private var cycleStart = Date()
    private var screenLocked = false
    /// The Mac slept or the screen locked since you last came back, which counts as a break.
    private var sleptOrLocked = false
    private var warnedThisCycle = false
    /// When a call, video or other activity that keeps the countdown running was last seen.
    private var lastBusy = Date.distantPast
    /// Your last input, for noticing the first return of a new day.
    private var lastActive = Settings.lastActive ?? Date()
    /// The menu's header while the menu is open, so ticks can keep it live.
    private weak var header: MenuHeaderView?

    private var workSeconds: Int { intervalOverride ?? Settings.workSeconds }
    private var breakSeconds: Int { breakOverride ?? Settings.breakSeconds }
    private var warnSeconds: Int { warnOverride ?? Settings.warnSeconds }
    /// No input for this long freezes the countdown; 0 never does.
    private var idleSeconds: Int { idleOverride ?? Settings.idleSeconds }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.onEnd = { [unowned self] in startWork() }
        overlay.onPostpone = { [unowned self] minutes in startWork(after: minutes * 60) }
        connectWarning()
        settings.onWorkChanged = { [unowned self] in startWork() }
        settings.onChanged = { [unowned self] in updateDisplay() }
        settings.onLanguageChanged = { [unowned self] in
            // The popover's labels are built once, so rebuild it in the new language.
            warning.close()
            warning = BreakWarning()
            connectWarning()
            updateDisplay()
        }
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        startWork()
        // `--welcome` shows the welcome window again (handy for testing).
        if Settings.isFirstLaunch || CommandLine.arguments.contains("--welcome") { showWelcome() }

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // After sleep or a locked screen you were most likely away, so that counts as a break.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenDidLock),
                                name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock),
                                name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    private func showWelcome() {
        let welcome = Welcome()
        welcome.onFinish = { [unowned self] in
            // Start the countdown over with the chosen interval.
            settings.refresh()
            startWork()
            self.welcome = nil
        }
        self.welcome = welcome
        welcome.show()
    }

    private func connectWarning() {
        warning.onStartNow = { [unowned self] in startBreak() }
        warning.onSnooze = { [unowned self] minutes in addTime(minutes: minutes) }
    }

    // MARK: Timer

    private func startWork(after seconds: Int? = nil) {
        overlay.close()
        warning.close()
        awayNotice.close()
        phase = .working
        let cycle = seconds ?? workSeconds
        cycleStart = Date()
        deadline = Date().addingTimeInterval(TimeInterval(cycle))
        // A cycle shorter than the warning window (e.g. a 1-minute postpone) gets no warning.
        warnedThisCycle = cycle <= warnSeconds
        updateDisplay()
    }

    private func startBreak() {
        warning.close()
        greeting.close()
        phase = .onBreak
        deadline = Date().addingTimeInterval(TimeInterval(breakSeconds))
        overlay.show(duration: TimeInterval(breakSeconds))
        Sound.breakStart.play()
        updateDisplay()
    }

    private func tick() {
        let input = secondsSinceLastInput()
        // Input behind the lock screen (typing the password) isn't a return yet.
        if !screenLocked {
            if input < 2, greetIfNewDay() { return }
            if phase != .working { noteActivity(at: Date().addingTimeInterval(-input)) }
        }
        switch phase {
        case .working:
            let idle = idleSeconds > 0 ? idleTime(input: input) : input
            if !screenLocked { noteActivity(at: Date().addingTimeInterval(-idle)) }
            if idleSeconds > 0, idle >= TimeInterval(idleSeconds) {
                goAway(idle: idle)
                return
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                // A break that comes due during a call waits until the call ends.
                if Settings.holdBreaksDuringCalls, Activity.calls.isHappening {
                    warning.close()
                    updateDisplay()
                } else {
                    startBreak()
                }
                return
            }
            if !warnedThisCycle, warnSeconds > 0, remaining <= TimeInterval(warnSeconds),
               let button = statusItem.button {
                warnedThisCycle = true
                warning.show(relativeTo: button, remaining: remaining)
                Sound.headsUp.play()
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
                Sound.breakOver.play()
                updateDisplay()
            } else {
                overlay.update(remaining: remaining)
                updateDisplay()
            }
        case .away:
            // Behind the lock screen the notice would go unseen, so wait for the unlock.
            if !screenLocked, input < 2 { comeBack() }
        case .breakOver, .paused:
            break
        }
    }

    /// Time without input, minus the time spent in a call, watching a video or similar, so
    /// those keep the countdown running. The checks only run once input has stopped for long.
    private func idleTime(input: TimeInterval) -> TimeInterval {
        if input >= TimeInterval(idleSeconds),
           Activity.allCases.contains(where: { Settings.keepsCounting($0) && $0.isHappening }) {
            lastBusy = Date()
        }
        return min(input, Date().timeIntervalSince(lastBusy))
    }

    private func noteActivity(at date: Date) {
        guard date > lastActive else { return }
        // Saving once a minute is precise enough for telling days apart.
        let save = date.timeIntervalSince(Settings.lastActive ?? .distantPast) >= 60
        lastActive = date
        if save { Settings.lastActive = date }
    }

    /// The first return on a new day greets you and starts a fresh countdown, whatever state
    /// the timer was left in. Days roll over at 4 AM, so working past midnight doesn't count.
    private func greetIfNewDay() -> Bool {
        let now = Date()
        let rollover: TimeInterval = 4 * 3600
        guard !Calendar.current.isDate(lastActive.addingTimeInterval(-rollover),
                                       inSameDayAs: now.addingTimeInterval(-rollover)),
              now.timeIntervalSince(lastActive) >= 3600 else { return false }
        lastActive = now
        Settings.lastActive = now
        sleptOrLocked = false
        startWork()
        if let button = statusItem.button {
            greeting.show(relativeTo: button, nextBreak: SettingsWindow.format(workSeconds))
        }
        return true
    }

    /// Freezes the countdown at the moment of your last input, so idle time isn't counted as work.
    private func goAway(idle: TimeInterval) {
        // Idle time from before this countdown started doesn't belong to it.
        let idle = min(idle, Date().timeIntervalSince(cycleStart))
        warning.close()
        awaySince = Date().addingTimeInterval(-idle)
        pausedRemaining = max(1, deadline.timeIntervalSinceNow + idle)
        phase = .away
        updateDisplay()
    }

    /// Picks the countdown back up where it stopped and says how long you were gone.
    /// If the Mac slept or locked meanwhile, that counts as a break and a new cycle starts.
    private func comeBack() {
        if greetIfNewDay() { return }
        let away = Date().timeIntervalSince(awaySince)
        let countedAsBreak = sleptOrLocked
        sleptOrLocked = false
        if countedAsBreak {
            startWork()
        } else {
            phase = .working
            cycleStart = Date()
            deadline = Date().addingTimeInterval(pausedRemaining)
            warnedThisCycle = pausedRemaining <= TimeInterval(warnSeconds)
            updateDisplay()
        }
        if let button = statusItem.button {
            awayNotice.show(relativeTo: button, away: away, countedAsBreak: countedAsBreak)
        }
    }

    @objc private func willSleep() {
        sleptOrLocked = true
        Settings.lastActive = lastActive
    }

    func applicationWillTerminate(_ notification: Notification) {
        Settings.lastActive = lastActive
    }

    @objc private func screenDidLock() {
        screenLocked = true
        sleptOrLocked = true
    }

    @objc private func didWake() {
        // With a password on wake, the unlock is the real return.
        if !screenLocked { userReturned() }
    }

    @objc private func screenDidUnlock() {
        screenLocked = false
        userReturned()
    }

    private func userReturned() {
        if greetIfNewDay() { return }
        switch phase {
        case .working: startWork()
        case .away: comeBack()
        case .onBreak, .breakOver, .paused: break
        }
        sleptOrLocked = false
    }

    // MARK: Menu

    private var remainingSeconds: Int { max(0, Int(deadline.timeIntervalSinceNow.rounded(.up))) }

    private func updateDisplay() {
        let title: String
        switch phase {
        case .working: title = waitingForCall ? L("After the call") : short(remainingSeconds)
        case .onBreak: title = L("Break %@", short(remainingSeconds))
        case .breakOver: title = L("Break done")
        case .paused: title = L("Paused %@", short(Int(pausedRemaining)))
        case .away: title = short(Int(pausedRemaining))
        }
        statusItem.button?.title = " " + title
        let image = phase == .paused || phase == .away ? SwayMark.pausedMenuBarImage : SwayMark.menuBarImage
        if statusItem.button?.image !== image { statusItem.button?.image = image }
        header?.update(headerState, animated: true)
    }

    /// The countdown ran out during a call, so the break waits for the call to end.
    private var waitingForCall: Bool { phase == .working && deadline.timeIntervalSinceNow <= 0 }

    private var headerState: HeaderState {
        switch phase {
        case .working where waitingForCall:
            HeaderState(caption: L("Next break"), value: L("After the call"), showsAddTime: true, mascot: .focus)
        case .working:
            HeaderState(caption: L("Next break in"), value: clock(remainingSeconds), showsAddTime: true, mascot: .focus)
        case .onBreak:
            HeaderState(caption: L("On a break"), value: clock(remainingSeconds), showsAddTime: false, mascot: .stretching)
        case .breakOver:
            HeaderState(caption: L("Break's over"), value: L("Welcome back"), showsAddTime: false, mascot: .cheering)
        case .paused:
            HeaderState(caption: L("%@ left", clock(Int(pausedRemaining))), value: L("Paused"), showsAddTime: true, mascot: .sleeping)
        case .away:
            HeaderState(caption: L("%@ left", clock(Int(pausedRemaining))), value: L("Away"), showsAddTime: true, mascot: .relaxed)
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
        case .onBreak: menu.addItem(item(L("End break now"), #selector(endBreak)))
        case .breakOver: menu.addItem(item(L("Back to work"), #selector(endBreak)))
        case .working, .paused, .away: menu.addItem(item(L("Take a break now"), #selector(breakNow)))
        }
        menu.addItem(item(phase == .paused ? L("Resume") : L("Pause"), #selector(togglePause)))
        menu.addItem(item(L("Restart timer"), #selector(restart)))
        menu.addItem(.separator())

        menu.addItem(submenu(title: L("Remind me every"), symbol: "timer", options: SettingsWindow.workPresets,
                             current: Settings.workSeconds, action: #selector(setWork(_:)),
                             customAction: #selector(customWork)))
        menu.addItem(submenu(title: L("Break length"), symbol: "cup.and.saucer", options: SettingsWindow.breakPresets,
                             current: Settings.breakSeconds, action: #selector(setBreak(_:)),
                             customAction: #selector(customBreak)))
        menu.addItem(.separator())

        if intervalOverride != nil || breakOverride != nil || warnOverride != nil || idleOverride != nil {
            let note = NSMenuItem(title: "Test mode: \(workSeconds)s work, \(breakSeconds)s break, \(warnSeconds)s warning, \(idleSeconds)s idle",
                                  action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }
        let settingsItem = item(L("Settings…"), #selector(showSettingsWindow), key: ",")
        settingsItem.attributedTitle = iconTitle(settingsItem.title, symbol: "gearshape")
        menu.addItem(settingsItem)
        menu.addItem(item(L("Quit Sway"), #selector(quit), key: "q"))
    }

    func menuDidClose(_ menu: NSMenu) {
        header = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Menu text with an SF Symbol in front. macOS 27 hides `NSMenuItem.image`, so the icon goes
    /// in the title, padded to a fixed width so the text lines up across items.
    private func iconTitle(_ text: String, symbol: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        guard let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: font.pointSize - 1, weight: .regular)) else {
            return NSAttributedString(string: text)
        }
        let attachment = NSTextAttachment()
        attachment.image = icon
        let size = icon.size
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
        // A blank image after the icon pads every icon to the same slot.
        let blank = NSImage(size: NSSize(width: max(1, font.pointSize + 10 - size.width), height: 1))
        let spacer = NSTextAttachment()
        spacer.image = blank
        spacer.bounds = NSRect(origin: .zero, size: blank.size)
        let title = NSMutableAttributedString(attachment: attachment)
        title.append(NSAttributedString(attachment: spacer))
        title.append(NSAttributedString(string: text))
        title.addAttribute(.font, value: font, range: NSRange(location: 0, length: title.length))
        return title
    }

    private func submenu(title: String, symbol: String, options: [Int], current: Int,
                         action: Selector, customAction: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(SettingsWindow.format(current))", action: nil, keyEquivalent: "")
        parent.attributedTitle = iconTitle(parent.title, symbol: symbol)
        let sub = NSMenu()
        for seconds in options {
            let option = item(SettingsWindow.format(seconds), action)
            option.tag = seconds
            option.state = seconds == current ? .on : .off
            sub.addItem(option)
        }
        sub.addItem(.separator())
        sub.addItem(item(L("Custom…"), customAction))
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
        case .paused, .away:
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
    // Not named like a standard settings action, which makes macOS 27 add a second gear.
    @objc private func showSettingsWindow() { settings.show() }

    @objc private func setWork(_ sender: NSMenuItem) {
        Settings.workSeconds = sender.tag
        settings.refresh()
        startWork()
    }

    @objc private func setBreak(_ sender: NSMenuItem) {
        Settings.breakSeconds = sender.tag
        settings.refresh()
        updateDisplay()
    }

    @objc private func customWork() {
        if let minutes = askMinutes(L("Remind me every how many minutes?"), current: Settings.workSeconds / 60) {
            Settings.workSeconds = minutes * 60
            settings.refresh()
            startWork()
        }
    }

    @objc private func customBreak() {
        if let minutes = askMinutes(L("Break length in minutes?"), current: Settings.breakSeconds / 60) {
            Settings.breakSeconds = minutes * 60
            settings.refresh()
            updateDisplay()
        }
    }

    private func askMinutes(_ question: String, current: Int) -> Int? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = question
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = String(current)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let minutes = Int(field.stringValue.trimmingCharacters(in: .whitespaces)),
              (1...600).contains(minutes) else { return nil }
        return minutes
    }

    @objc private func togglePause() {
        if phase == .paused {
            phase = .working
            cycleStart = Date()
            deadline = Date().addingTimeInterval(pausedRemaining)
        } else if phase == .away {
            // Already frozen; just stop it from resuming on its own.
            phase = .paused
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
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
