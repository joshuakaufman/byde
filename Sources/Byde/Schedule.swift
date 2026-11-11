import Foundation

/// When each nudge is due for one window. Pure, so it can be self-checked.
/// `anchor` is when nudge 1 is due: the window start, or `snoozeDelay` after a snooze;
/// nil when a snooze would have ended after nudge 3 (nudge 3 then fires at its normal time).
struct Schedule {
    /// Nudge 2 comes this long after the latest nudge 1; nudge 3 this long before the window ends.
    static let nudge2Delay: TimeInterval = 1200
    static let nudge3Lead: TimeInterval = 900
    /// Snooze re-shows nudge 1 this long after the click.
    static let snoozeDelay: TimeInterval = 600

    let start: Date
    let end: Date
    var anchor: Date?

    init(start: Date, end: Date, anchor: Date? = nil, noNudge1: Bool = false) {
        self.start = start
        self.end = end
        self.anchor = noNudge1 ? nil : (anchor ?? start)
    }

    /// 15 min before the window ends; none if the window is shorter than 20 min (only nudge 1 then).
    var n3: Date? { end.timeIntervalSince(start) >= Self.nudge2Delay ? end.addingTimeInterval(-Self.nudge3Lead) : nil }
    /// 20 min after the latest nudge 1; skipped if that is at or after nudge 3.
    var n2: Date? {
        guard let a = anchor, let n3 else { return nil }
        let t = a.addingTimeInterval(Self.nudge2Delay)
        return t < n3 ? t : nil
    }

    /// The most recent nudge that is due (3, 2, 1) or 0. Waking late shows only the latest one.
    func due(at now: Date) -> Int {
        guard now < end else { return 0 }
        if let t = n3, now >= t { return 3 }
        if let t = n2, now >= t { return 2 }
        if let t = anchor, now >= t { return 1 }
        return 0
    }

    /// Snooze from `now`: nudge 1 returns after `snoozeDelay` unless that is at or after nudge 3.
    func snoozed(from now: Date) -> Schedule {
        let t = now.addingTimeInterval(Self.snoozeDelay)
        if let n3, t >= n3 { return Schedule(start: start, end: end, noNudge1: true) }
        return Schedule(start: start, end: end, anchor: t)
    }

    static func selfTest() {
        let s = Date(timeIntervalSince1970: 13 * 3600), e = s.addingTimeInterval(7200)   // 13:00–15:00
        let m: (Double) -> Date = { s.addingTimeInterval($0 * 60) }
        var x = Schedule(start: s, end: e)
        precondition(x.anchor == m(0) && x.n2 == m(20) && x.n3 == m(105), "13:00 / 13:20 / 14:45")
        precondition(x.due(at: m(-1)) == 0 && x.due(at: m(0)) == 1 && x.due(at: m(20)) == 2 && x.due(at: m(105)) == 3)
        precondition(x.due(at: m(60)) == 2, "waking late shows the latest due nudge")
        precondition(x.due(at: m(120)) == 0, "silent after the window")
        x = x.snoozed(from: m(5))
        precondition(x.anchor == m(15) && x.n2 == m(35), "snooze restarts the nudge 2 clock")
        precondition(x.snoozed(from: m(95)).anchor == nil && x.snoozed(from: m(100)).due(at: m(105)) == 3, "snooze reaching nudge 3")
        precondition(Schedule(start: s, end: m(19)).n3 == nil && Schedule(start: s, end: m(19)).n2 == nil, "<20 min: nudge 1 only")
        precondition(Schedule(start: s, end: m(30)).n2 == nil, "nudge 2 would land after nudge 3")
        print("selftest ok")
    }
}
