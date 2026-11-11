import AppKit
import SwiftUI

@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()

    enum Status: String, Codable { case waiting, nudged, done, skipped }
    struct Day: Codable {
        var key = ""
        var status = Status.waiting
    }

    // Persisted per-day state; everything below it is rebuilt on relaunch.
    @Published var day: Day {
        didSet {
            save()
            #if DEBUG
            if oldValue.status != day.status { iconPreview = nil }
            #endif
        }
    }
    #if DEBUG
    @Published var iconPreview: Bool?              // debug: overrides the menu bar icon until the next state change
    var iconDone: Bool { iconPreview ?? (day.status == .done) }
    #else
    var iconDone: Bool { day.status == .done }
    #endif
    @Published var stage = 0                      // 0 hidden, 1 first nudge, 2 second nudge, 3 closing nudge (centred)
    @Published var sessionEnd: Date?
    @Published var sessionOver = false             // timer finished; end screen showing
    @Published var snoozedToday = false
    @Published var statusLine = "Waiting"
    var sessionMinutes = 0

    private var shownAt = Date()
    private var level = 0                         // highest nudge shown since the last snooze
    private var snoozeUntil: Date?                // nudge 1 time after a snooze
    private var noNudge1 = false                  // a snooze ran past nudge 3
    private var hold = false                      // debug: scheduler stays out of the way
    private var timerWindow: TimerWindow?
    private var sessionStarted = false            // lead-in countdown finished
    private var leadEnd = Date()
    private var sessionSource = "nudge"
    private var previousApp: NSRunningApplication?
    private lazy var nudgePanel = FloatPanel(AnyView(NudgeView()))

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["startMin": 660, "endMin": 780, "days": "2,3,4,5,6"])
        if let data = d.data(forKey: "day"), let v = try? JSONDecoder().decode(Day.self, from: data) {
            day = v
        } else {
            day = Day()
        }
    }

    // MARK: prefs

    private var startMin: Int { UserDefaults.standard.integer(forKey: "startMin") }
    private var endMin: Int { UserDefaults.standard.integer(forKey: "endMin") }
    var endText: String { fmt(at(endMin)) }

    private func at(_ minutes: Int, _ d: Date = Date()) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: d)!
    }
    private func isActiveDay(_ d: Date) -> Bool {
        let days = Set((UserDefaults.standard.string(forKey: "days") ?? "").split(separator: ",").compactMap { Int($0) })
        return days.contains(Calendar.current.component(.weekday, from: d))
    }
    private func fmt(_ d: Date) -> String { d.formatted(.dateTime.hour().minute()) }

    // MARK: lifecycle

    func start() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func rollDay(_ now: Date) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let k = f.string(from: now)
        guard day.key != k else { return }
        day = Day(key: k)
        level = 0; snoozeUntil = nil; noNudge1 = false; hold = false; snoozedToday = false
        hideAll()
    }

    /// The menu status line. Done and skipped win over the time-based states.
    /// The done sign-off depends only on the day of the year, so it never changes while the menu is open.
    private func updateStatusLine(_ now: Date) {
        let text: String
        switch day.status {
        case .done:
            let doy = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0
            text = "Meditated. " + ["Great work!", "Excellent job!", "Nicely done!"][doy % 3]
        case .skipped: text = "Skipped"
        default:
            if !isActiveDay(now) { text = "No window today" }
            else if day.status == .waiting, now < at(startMin, now) { text = "Waiting for window" }
            else if now >= at(endMin, now) { text = "Window ended." }
            else { text = day.status == .waiting ? "Waiting" : "Nudged" }
        }
        if statusLine != text { statusLine = text }
    }

    private func schedule(_ now: Date) -> Schedule {
        Schedule(start: at(startMin, now), end: at(endMin, now), anchor: snoozeUntil, noNudge1: noNudge1)
    }

    private func tick() {
        let now = Date()
        rollDay(now)
        sessionTick(now)
        updateStatusLine(now)
        if hold || sessionEnd != nil { return }       // no nudges while a session is running
        guard isActiveDay(now), day.status == .waiting || day.status == .nudged else { return }

        let sched = schedule(now)
        if now >= sched.end {
            if stage != 0 { hideAll(); Log.add("window_closed") }
            return
        }
        let n = sched.due(at: now)
        if n > level { show(n, n == 1 && snoozeUntil != nil ? "snooze" : nil) }
    }

    // MARK: nudges

    private func bell() { NSSound(named: "Glass")?.play() }

    private func show(_ n: Int, _ why: String? = nil) {
        stage = n; level = n; shownAt = Date(); day.status = .nudged
        Log.add("nudge_shown", nudge: n, detail: why)
        nudgePanel.present(center: n == 3, animate: n == 3)
        if n >= 2 { bell() }
        if n == 2 { nudgePanel.pulse() }
    }

    private func hideAll() {
        stage = 0
        nudgePanel.orderOut(nil)
    }

    // MARK: responses

    private func respond(_ action: String, _ status: Status? = nil) {
        Log.add("response", nudge: stage, detail: action, waited: Int(Date().timeIntervalSince(shownAt)))
        hold = false
        hideAll()
        if let status { day.status = status }
    }

    func skip() { respond("skip_today", .skipped) }
    func snooze() {
        let next = schedule(Date()).snoozed(from: Date())
        respond("snooze_10")
        snoozedToday = true
        level = 0; snoozeUntil = next.anchor; noNudge1 = next.anchor == nil
    }

    // MARK: meditating

    /// "Already done": counts as today's session with no timer, countdown or Focus Shortcuts.
    func alreadyMeditated() {
        guard sessionEnd == nil else { return }
        respond("already_meditated")
        day.status = .done
        Log.add("session_completed", detail: "manual", source: "manual")
    }

    /// The meditation app link: opens the site and counts as today's session. No Focus Shortcuts, no timer.
    /// `source` is "link" (nudge card) or "menu-link" (Meditate now).
    func linkSession(source: String) {
        guard sessionEnd == nil, let url = LinkStore.shared.openURL else { return }
        if source == "link" { respond("open_link") } else { hold = false; hideAll() }
        NSWorkspace.shared.open(url)
        day.status = .done
        Log.add("session_completed", detail: "link", source: source)
    }

    /// `source` is "nudge" (panel buttons) or "menu" (Meditate now).
    /// Nudge sessions mark the day done on pick; menu sessions only once the countdown has finished.
    func meditate(_ minutes: Int, source: String = "nudge") {
        guard sessionEnd == nil else { return }
        if source == "nudge" { respond("meditate_\(minutes)") } else { hold = false; hideAll() }
        sessionSource = source
        sessionMinutes = minutes
        sessionOver = false
        let me = ProcessInfo.processInfo.processIdentifier
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == me ? nil : $0 }
        runShortcut("Byde Focus On")
        leadEnd = Date().addingTimeInterval(10)       // 10 s countdown, not part of the duration
        let end = leadEnd.addingTimeInterval(Double(minutes) * 60)
        sessionEnd = end
        sessionStarted = false
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w = TimerWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: MeditationView(leadEnd: leadEnd, end: end))
        w.level = .screenSaver
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        timerWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Called from `tick`. Both phases compare the clock with fixed timestamps, so a late tick can't stretch a session.
    private func sessionTick(_ now: Date) {
        guard let end = sessionEnd, !sessionOver else { return }
        if !sessionStarted, now >= leadEnd {
            sessionStarted = true
            Log.add("session_started", detail: "\(sessionMinutes) min", source: sessionSource)
        }
        if now >= end {
            sessionOver = true
            day.status = .done                       // only a session that runs to the end counts as today's
            bell()
            Log.add("session_completed", detail: "\(sessionMinutes) min", source: sessionSource)
            }
    }

    /// "End early" during the countdown or the timer.
    func endEarly() {
        guard let end = sessionEnd, !sessionOver else { return }
        if sessionStarted {
            Log.add("session_ended_early", detail: "\(Int(max(0, end.timeIntervalSinceNow)))s left", source: sessionSource)
        }   // cancelled during the countdown: nothing to log
        finishSession()
    }

    /// Closes the full-screen view, runs Focus Off and hands focus back to the app you were in.
    func finishSession() {
        guard sessionEnd != nil else { return }
        sessionEnd = nil; sessionOver = false
        timerWindow?.orderOut(nil); timerWindow = nil
        runShortcut("Byde Focus Off")
        if let app = previousApp, !app.isTerminated { app.activate() }
        previousApp = nil
    }

    private func runShortcut(_ name: String) {
        Task.detached {
            let exists = Self.shortcuts(["list"]).split(separator: "\n").contains { $0 == name }
            if exists { _ = Self.shortcuts(["run", name]) }
            await MainActor.run { Log.add(exists ? "shortcut_run" : "shortcut_missing", detail: name) }
        }
    }

    nonisolated private static func shortcuts(_ args: [String]) -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = args
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: debug (Debug builds only)

    #if DEBUG
    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func scheduleText() -> String {
        let now = Date(), sch = schedule(now)
        var s = "Window \(fmt(sch.start))–\(fmt(sch.end))"
        if !isActiveDay(now) { return s + "\nToday isn't an enabled day, so nothing will fire." }
        s += "\n\nNudge 1: " + (sch.anchor.map(fmt) ?? "none (snooze ran past nudge 3)")
        s += "\nNudge 2: " + (sch.n2.map(fmt) ?? "none")
        s += "\nNudge 3: " + (sch.n3.map(fmt) ?? "none (window under 20 min)")
        s += "\n\nToday: \(day.status.rawValue)."
        if day.status == .done || day.status == .skipped { return s + " No more nudges." }
        let n = sch.due(at: now)
        s += n > 0 ? " Nudge \(n) is due now." : " Nothing due right now."
        return s
    }

    func debug(_ what: String) {
        Log.add("debug", detail: what)
        switch what {
        case "schedule": alert("Today's nudge schedule", scheduleText())
        case "nudge1": hold = true; hideAll(); show(1, "debug")
        case "nudge2": hold = true; hideAll(); show(2, "debug")
        case "nudge3": hold = true; hideAll(); show(3, "debug")
        case "refetchFavicon":
            if LinkStore.shared.isSet { LinkStore.shared.refetchFavicon() } else { alert("Refetch favicon", "Set a website in Settings first.") }
        case "iconWaiting": iconPreview = false
        case "iconDone": iconPreview = true
        case "reveal":
            try? FileManager.default.createDirectory(at: Log.dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Log.dir)
        default:  // reset
            hideAll()
            level = 0; snoozeUntil = nil; noNudge1 = false; hold = false; snoozedToday = false
            day = Day(key: "")
            rollDay(Date())
        }
    }
    #endif

    private func save() {
        if let d = try? JSONEncoder().encode(day) { UserDefaults.standard.set(d, forKey: "day") }
    }
}
