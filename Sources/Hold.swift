import AppKit

/// Why a break that's due waits a little before starting. None of the checks needs a permission.
enum Hold: Equatable {
    /// A call or meeting (microphone or camera in use), held until it ends.
    case call
    /// Typing or dragging, held until a short pause, for up to `typingLimit`.
    case typing
    /// The app in front is in full screen or one you picked, held until you leave it.
    case app(String)

    /// Typing holds a break for at most this long, so a steady typist still gets breaks.
    static let typingLimit: TimeInterval = 60
    /// Typing counts as stopped after this long without a key press.
    private static let typingPause: TimeInterval = 3

    /// What's holding a break right now, if anything; `waited` is how long it's been held already.
    static func current(waited: TimeInterval) -> Hold? {
        if Settings.holdBreaksDuringCalls, Activity.calls.isHappening { return .call }
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            let name = app.localizedName ?? ""
            if let id = app.bundleIdentifier, Settings.focusApps.contains(id) { return .app(name) }
            if Settings.holdBreaksInFullScreen, isFullScreen(app) { return .app(name) }
        }
        if Settings.holdBreaksWhileTyping, waited < typingLimit, isTyping() { return .typing }
        return nil
    }

    /// The menu bar text while a break is held.
    var title: String {
        switch self {
        case .call: L("After the call")
        case .typing: L("In a moment")
        case .app(let name): L("After %@", name)
        }
    }

    private static func isTyping() -> Bool {
        let state = CGEventSourceStateID.combinedSessionState
        return CGEventSource.secondsSinceLastEventType(state, eventType: .keyDown) < typingPause
            || NSEvent.pressedMouseButtons != 0
    }

    /// One of the app's windows covers a whole display: a full-screen app, a game, a slideshow or a video.
    private static func isFullScreen(_ app: NSRunningApplication) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first?.frame else { return false }
        // Window bounds count y down from the top of the primary display; screen frames count up.
        let screens = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: primary.maxY - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let info = window[kCGWindowBounds as String] as! CFDictionary?,
                  let bounds = CGRect(dictionaryRepresentation: info) else { return false }
            return screens.contains(bounds)
        }
    }
}
