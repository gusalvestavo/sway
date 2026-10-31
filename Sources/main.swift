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

    /// Length of the long break that replaces a regular one every few breaks; 0 turns long breaks off.
    static var longBreakSeconds: Int {
        get { defaults.object(forKey: "longBreakSeconds") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "longBreakSeconds") }
    }

    /// One break in this many is a long one.
    static var longBreakEvery: Int {
        get { defaults.object(forKey: "longBreakEvery") as? Int ?? 4 }
        set { defaults.set(newValue, forKey: "longBreakEvery") }
    }

    /// How often the blink and posture nudges come between breaks; 0 turns each off.
    static var blinkSeconds: Int {
        get { defaults.object(forKey: "blinkSeconds") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "blinkSeconds") }
    }

    static var postureSeconds: Int {
        get { defaults.object(forKey: "postureSeconds") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "postureSeconds") }
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

    /// Whether a break that comes due while you're typing or dragging waits for a short pause.
    static var holdBreaksWhileTyping: Bool {
        get { defaults.object(forKey: "holdBreaksWhileTyping") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "holdBreaksWhileTyping") }
    }

    /// Whether a break waits while the app in front is in full screen. Off by default, since
    /// some people work in full screen all day.
    static var holdBreaksInFullScreen: Bool {
        get { defaults.bool(forKey: "holdBreaksInFullScreen") }
        set { defaults.set(newValue, forKey: "holdBreaksInFullScreen") }
    }

    /// Bundle identifiers of apps that hold a break while they're in front.
    static var focusApps: [String] {
        get { defaults.stringArray(forKey: "focusApps") ?? [] }
        set { defaults.set(newValue, forKey: "focusApps") }
    }

    /// Whether Sway only runs during the work days and hours below.
    static var workHoursOn: Bool {
        get { defaults.bool(forKey: "workHoursOn") }
        set { defaults.set(newValue, forKey: "workHoursOn") }
    }

    /// Work days as `Calendar` weekdays (1 is Sunday); Monday to Friday by default.
    static var workDays: [Int] {
        get { defaults.array(forKey: "workDays") as? [Int] ?? [2, 3, 4, 5, 6] }
        set { defaults.set(newValue, forKey: "workDays") }
    }

    /// Start and end of work hours, in minutes after midnight.
    static var workStart: Int {
        get { defaults.object(forKey: "workStart") as? Int ?? 9 * 60 }
        set { defaults.set(newValue, forKey: "workStart") }
    }

    static var workEnd: Int {
        get { defaults.object(forKey: "workEnd") as? Int ?? 18 * 60 }
        set { defaults.set(newValue, forKey: "workEnd") }
    }

    /// Breaks at set times of day.
    static var plannedBreaks: [PlannedBreak] {
        get { defaults.data(forKey: "plannedBreaks").flatMap { try? JSONDecoder().decode([PlannedBreak].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "plannedBreaks") }
    }

    /// When each planned break (by id) last started or was skipped, so it happens once a day,
    /// even across a relaunch.
    static var plannedBreaksDone: [String: Date] {
        get { defaults.dictionary(forKey: "plannedBreaksDone") as? [String: Date] ?? [:] }
        set { defaults.set(newValue, forKey: "plannedBreaksDone") }
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
let longBreakOverride = argument("--long-break-seconds")

/// Seconds since the last keyboard, mouse or trackpad event in this login session.
/// Needs no permission, unlike watching the events themselves.
func secondsSinceLastInput() -> TimeInterval {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// `away`: no input for a while, so the work countdown is frozen until you're back.
    /// `offHours`: outside work hours, so there's no countdown until they begin.
    enum Phase { case working, onBreak, breakOver, paused, away, offHours }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let overlay = BreakOverlay()
    private var warning = BreakWarning()
    private let settings = SettingsWindow()
    private let awayNotice = AwayNotice()
    private let greeting = Greeting()
    private let nudgeNotice = NudgeNotice()
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
    /// What's keeping a break that's due from starting, and since when.
    private var hold: Hold?
    private var heldSince = Date()
    /// How far snoozes pushed each planned break (by id) today.
    private var plannedSnoozes: [UUID: TimeInterval] = [:]
    /// The planned break the heads-up was last shown for.
    private var warnedPlanned: UUID?
    /// Planned breaks whose time came while you were working, waiting to start.
    private var plannedPending: Set<UUID> = []
    /// The planned break on screen, if the current break is one.
    private var currentPlanned: PlannedBreak?
    /// The previous tick, to notice a planned break's time passing (and sleep, as a long gap).
    private var lastTick = Date()
    /// Breaks since the last long one, and the count before the break on screen started, so
    /// snoozing that break doesn't count it twice.
    private var breaksSinceLong = 0
    private var breaksBeforeThis = 0
    /// Working time since each blink or posture nudge last showed; breaks and time away don't add to it.
    private var nudgeWorked: [Nudge: TimeInterval] = [:]
    /// A nudge that's due but held back (by a call, say) tries again at this time.
    private var nudgeRetry = Date.distantPast
    /// "Start reminders anyway" outside work hours lasts until this time.
    private var offHoursOverride = Date.distantPast
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
    private var longBreakSeconds: Int { longBreakOverride ?? Settings.longBreakSeconds }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.onEnd = { [unowned self] in startWork() }
        overlay.onPostpone = { [unowned self] minutes in postpone(minutes: minutes) }
        connectWarning()
        settings.onWorkChanged = { [unowned self] in startWork() }
        settings.onChanged = { [unowned self] in updateDisplay() }
        settings.onNudgesChanged = { [unowned self] in nudgeWorked = [:] }
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
        warning.onStartNow = { [unowned self] in startBreak(planned: nextBreak.planned) }
        warning.onSnooze = { [unowned self] minutes in addTime(minutes: minutes) }
    }

    // MARK: Timer

    /// Outside work hours (when they're on), unless you asked for reminders anyway.
    private var isOffHours: Bool {
        Settings.workHoursOn && !WorkHours.contains(Date()) && offHoursOverride <= Date()
    }

    private func startWork(after seconds: Int? = nil) {
        overlay.close()
        warning.close()
        awayNotice.close()
        hold = nil
        currentPlanned = nil
        // Every path back to work goes through here, so this is the one place that checks the hours.
        if isOffHours {
            phase = .offHours
            updateDisplay()
            return
        }
        phase = .working
        let cycle = seconds ?? workSeconds
        cycleStart = Date()
        deadline = Date().addingTimeInterval(TimeInterval(cycle))
        // A cycle shorter than the warning window (e.g. a 1-minute postpone) gets no warning.
        warnedThisCycle = cycle <= warnSeconds
        updateDisplay()
    }

    /// Starts `planned` with its own name and length, or a regular break.
    private func startBreak(planned: PlannedBreak? = nil) {
        warning.close()
        greeting.close()
        nudgeNotice.close()
        phase = .onBreak
        hold = nil
        if let planned { markDone(planned) }
        currentPlanned = planned
        let long = planned == nil && longBreakNext
        let length = planned.map { TimeInterval($0.length * 60) } ?? TimeInterval(long ? longBreakSeconds : breakSeconds)
        breaksBeforeThis = breaksSinceLong
        countBreak(lasting: length)
        // A nudge held back until now is covered by the break.
        for nudge in Nudge.allCases where nudge.seconds > 0 && nudgeWorked[nudge, default: 0] >= TimeInterval(nudge.seconds) {
            nudgeWorked[nudge] = 0
        }
        deadline = Date().addingTimeInterval(length)
        overlay.show(duration: length, title: planned?.title ?? (long ? L("Time for a long break") : nil))
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
        // Work hours ending stops the countdown; their start begins a fresh one.
        switch phase {
        case .working, .away: if isOffHours { startWork(); return }
        case .offHours: if !isOffHours { startWork(); return }
        case .onBreak, .breakOver, .paused: break
        }
        checkPlannedTimes()
        switch phase {
        case .working:
            let idle = idleSeconds > 0 ? idleTime(input: input) : input
            if !screenLocked { noteActivity(at: Date().addingTimeInterval(-idle)) }
            if idleSeconds > 0, idle >= TimeInterval(idleSeconds) {
                goAway(idle: idle)
                return
            }
            let next = nextBreak
            let remaining = next.date.timeIntervalSinceNow
            if remaining <= 0 {
                // A break that comes due during a call, while typing or in a focus app waits a bit.
                if hold == nil { heldSince = Date() }
                hold = Hold.current(waited: Date().timeIntervalSince(heldSince))
                if hold != nil {
                    warning.close()
                    updateDisplay()
                } else {
                    startBreak(planned: next.planned)
                }
                return
            }
            hold = nil
            checkNudges(untilBreak: remaining)
            // Each planned break gets its own heads-up, apart from the regular cycle's.
            let warned = next.planned.map { $0.id == warnedPlanned } ?? warnedThisCycle
            if !warned, warnSeconds > 0, remaining <= TimeInterval(warnSeconds),
               let button = statusItem.button {
                if let planned = next.planned { warnedPlanned = planned.id } else { warnedThisCycle = true }
                nudgeNotice.close()
                warning.show(relativeTo: button, remaining: remaining, long: next.planned == nil && longBreakNext)
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
        case .breakOver, .paused, .offHours:
            break
        }
    }

    // MARK: Planned breaks

    private func due(_ planned: PlannedBreak) -> Date? {
        planned.due(on: Date(), snoozed: plannedSnoozes[planned.id] ?? 0)
    }

    /// A planned break becomes due only when a tick sees its time pass, so adding one for a time
    /// that's already gone, or relaunching after it, doesn't start it. If its time passes while
    /// the Mac sleeps, or you're away, paused or outside work hours, it's skipped. During another
    /// break it waits and starts right after.
    private func checkPlannedTimes() {
        let now = Date()
        let slept = now.timeIntervalSince(lastTick) > 5
        let previous = lastTick
        lastTick = now
        for planned in Settings.plannedBreaks where !isDone(planned) {
            guard let due = due(planned) else { continue }
            if plannedPending.contains(planned.id) {
                // Held for over an hour, e.g. by a long call: too late now.
                if due < now.addingTimeInterval(-PlannedBreak.grace) { markDone(planned) }
            } else if due > previous, due <= now {
                if slept || [.away, .paused, .offHours].contains(phase) {
                    markDone(planned)
                } else {
                    plannedPending.insert(planned.id)
                }
            }
        }
    }

    /// The next break: the regular countdown's, or a planned one that's due or comes first.
    private var nextBreak: (date: Date, planned: PlannedBreak?) {
        let now = Date()
        let planned = Settings.plannedBreaks.compactMap { planned -> (Date, PlannedBreak)? in
            guard !isDone(planned), let due = due(planned) else { return nil }
            if plannedPending.contains(planned.id) { return (min(due, now), planned) }
            return due > now ? (due, planned) : nil
        }.min { $0.0 < $1.0 }
        if let (due, next) = planned, due < deadline { return (due, next) }
        return (deadline, nil)
    }

    /// Moves `planned` to start at `date` instead.
    private func reschedule(_ planned: PlannedBreak, to date: Date) {
        guard let base = planned.due(on: Date(), snoozed: 0) else { return }
        plannedSnoozes[planned.id] = date.timeIntervalSince(base)
        plannedPending.remove(planned.id)
    }

    /// The break screen's +1/+3/+5 min: a planned break comes back later as itself.
    private func postpone(minutes: Int) {
        breaksSinceLong = breaksBeforeThis
        guard let planned = currentPlanned else {
            startWork(after: minutes * 60)
            return
        }
        Settings.plannedBreaksDone[planned.id.uuidString] = nil
        warnedPlanned = nil
        reschedule(planned, to: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        startWork()
    }

    private func isDone(_ planned: PlannedBreak) -> Bool {
        Settings.plannedBreaksDone[planned.id.uuidString].map(Calendar.current.isDateInToday) ?? false
    }

    private func markDone(_ planned: PlannedBreak) {
        Settings.plannedBreaksDone[planned.id.uuidString] = Date()
        plannedSnoozes[planned.id] = nil
        plannedPending.remove(planned.id)
    }

    // MARK: Long breaks and nudges

    /// The next regular break is a long one.
    private var longBreakNext: Bool {
        longBreakSeconds > 0 && breaksSinceLong + 1 >= Settings.longBreakEvery
    }

    /// Counts a break toward the next long one; one at least as long as a long break, such as
    /// lunch or a long time away, starts the count over.
    private func countBreak(lasting seconds: TimeInterval) {
        breaksSinceLong = longBreakSeconds > 0 && seconds >= TimeInterval(longBreakSeconds) ? 0 : breaksSinceLong + 1
    }

    /// Counts a second of work toward each nudge and shows one that's due. It waits while a break
    /// is close (and the break then covers it), while something would hold a break (a call, a focus
    /// app, full screen if that's on), or while another popover is up.
    private func checkNudges(untilBreak remaining: TimeInterval) {
        let now = Date()
        for nudge in Nudge.allCases where nudge.seconds > 0 { nudgeWorked[nudge, default: 0] += 1 }
        guard let nudge = Nudge.allCases.first(where: { $0.seconds > 0 && nudgeWorked[$0, default: 0] >= TimeInterval($0.seconds) }),
              now >= nudgeRetry, remaining > TimeInterval(warnSeconds + 30) else { return }
        if warning.isShown || awayNotice.isShown || greeting.isShown || nudgeNotice.isShown
            || Hold.current(waited: Hold.typingLimit) != nil {
            nudgeRetry = now.addingTimeInterval(30)
        } else if let button = statusItem.button {
            nudgeWorked[nudge] = 0
            nudgeNotice.show(nudge, relativeTo: button)
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
        // Outside work hours there's no countdown to announce.
        if isOffHours { return false }
        let rollover: TimeInterval = 4 * 3600
        guard !Calendar.current.isDate(lastActive.addingTimeInterval(-rollover),
                                       inSameDayAs: now.addingTimeInterval(-rollover)),
              now.timeIntervalSince(lastActive) >= 3600 else { return false }
        lastActive = now
        Settings.lastActive = now
        sleptOrLocked = false
        breaksSinceLong = 0
        nudgeWorked = [:]
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
        hold = nil
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
            countBreak(lasting: away)
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
        case .onBreak, .breakOver, .paused, .offHours: break
        }
        sleptOrLocked = false
    }

    // MARK: Menu

    private var remainingSeconds: Int { secondsUntil(deadline) }

    private func secondsUntil(_ date: Date) -> Int { max(0, Int(date.timeIntervalSinceNow.rounded(.up))) }

    private func updateDisplay() {
        let title: String
        switch phase {
        case .working: title = heldBreak?.title ?? short(secondsUntil(nextBreak.date))
        case .onBreak: title = L("Break %@", short(remainingSeconds))
        case .breakOver: title = L("Break done")
        case .paused: title = L("Paused %@", short(Int(pausedRemaining)))
        case .away: title = short(Int(pausedRemaining))
        case .offHours: title = L("Off hours")
        }
        statusItem.button?.title = " " + title
        let image = [.paused, .away, .offHours].contains(phase) ? SwayMark.pausedMenuBarImage : SwayMark.menuBarImage
        if statusItem.button?.image !== image { statusItem.button?.image = image }
        header?.update(headerState, animated: true)
    }

    /// The countdown ran out, but a call, typing or a focus app holds the break back.
    private var heldBreak: Hold? { phase == .working ? hold : nil }

    private var headerState: HeaderState {
        switch phase {
        case .working where heldBreak != nil:
            HeaderState(caption: L("Next break"), value: heldBreak!.title, showsAddTime: true, mascot: .focus)
        case .working:
            countdownHeader(nextBreak)
        case .onBreak:
            HeaderState(caption: L("On a break"), value: clock(remainingSeconds), showsAddTime: false, mascot: .stretching)
        case .breakOver:
            HeaderState(caption: L("Break's over"), value: L("Welcome back"), showsAddTime: false, mascot: .cheering)
        case .paused:
            HeaderState(caption: L("%@ left", clock(Int(pausedRemaining))), value: L("Paused"), showsAddTime: true, mascot: .sleeping)
        case .away:
            HeaderState(caption: L("%@ left", clock(Int(pausedRemaining))), value: L("Away"), showsAddTime: true, mascot: .relaxed)
        case .offHours:
            HeaderState(caption: L("Outside work hours"), value: WorkHours.nextStart(after: Date()).map(backAt) ?? L("Off hours"),
                        showsAddTime: false, mascot: .napping)
        }
    }

    /// "Next break in 24:13", "Long break in 24:13", or "Lunch in 4:59" when a planned break comes first.
    private func countdownHeader(_ next: (date: Date, planned: PlannedBreak?)) -> HeaderState {
        HeaderState(caption: next.planned.map { L("%@ in", $0.title) } ?? (longBreakNext ? L("Long break in") : L("Next break in")),
                    value: clock(secondsUntil(next.date)), showsAddTime: true, mascot: .focus)
    }

    /// "Back at 9:00", or with the weekday when that's not today, e.g. "Back Mon 9:00".
    private func backAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        let today = Calendar.current.isDateInToday(date)
        formatter.setLocalizedDateFormatFromTemplate(today ? "jmm" : "EEEjmm")
        return today ? L("Back at %@", formatter.string(from: date)) : L("Back %@", formatter.string(from: date))
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
        case .offHours: menu.addItem(item(L("Start reminders anyway"), #selector(remindAnyway)))
        }
        if phase != .offHours {
            menu.addItem(item(phase == .paused ? L("Resume") : L("Pause"), #selector(togglePause)))
            menu.addItem(item(L("Restart timer"), #selector(restart)))
        }
        menu.addItem(.separator())

        menu.addItem(submenu(title: L("Remind me every"), symbol: "timer", options: SettingsWindow.workPresets,
                             current: Settings.workSeconds, action: #selector(setWork(_:)),
                             customAction: #selector(customWork)))
        menu.addItem(submenu(title: L("Break length"), symbol: "cup.and.saucer", options: SettingsWindow.breakPresets,
                             current: Settings.breakSeconds, action: #selector(setBreak(_:)),
                             customAction: #selector(customBreak)))
        menu.addItem(.separator())

        if intervalOverride != nil || breakOverride != nil || warnOverride != nil || idleOverride != nil || longBreakOverride != nil {
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
            // Snoozing just before a planned break moves that break instead of the regular one.
            let next = nextBreak
            if let planned = next.planned {
                reschedule(planned, to: max(next.date, Date()).addingTimeInterval(extra))
                if nextBreak.date.timeIntervalSinceNow > TimeInterval(warnSeconds) {
                    warnedPlanned = nil
                    warning.close()
                }
                break
            }
            deadline += extra
            // Re-arm the warning if the extra time moved the break out of the warning window.
            if deadline.timeIntervalSinceNow > TimeInterval(warnSeconds) {
                warnedThisCycle = false
                warning.close()
            }
        case .paused, .away:
            pausedRemaining += extra
        case .onBreak, .breakOver, .offHours:
            return
        }
        statusItem.menu?.cancelTracking()
        updateDisplay()
    }

    @objc private func breakNow() { startBreak() }

    /// Outside work hours, starts the countdown and keeps it going until work hours next begin.
    @objc private func remindAnyway() {
        offHoursOverride = WorkHours.nextStart(after: Date()) ?? .distantFuture
        startWork()
    }
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
