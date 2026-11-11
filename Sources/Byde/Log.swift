import Foundation

struct Entry: Codable {
    let ts: String
    let event: String
    var nudge: Int?
    var detail: String?
    var waited: Int?
    var source: String?
}

/// Append-only JSON Lines, one file per month (`log-YYYY-MM.jsonl`). Entries are appended without reading
/// anything back; old months are never touched or deleted. Nothing in the app reads the log.
enum Log {
    static var dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Byde")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f
    }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    static func add(_ event: String, nudge: Int? = nil, detail: String? = nil, waited: Int? = nil, source: String? = nil) {
        let ts = stamp.string(from: Date())       // local time; its first 7 characters are the month (YYYY-MM)
        append(Entry(ts: ts, event: event, nudge: nudge, detail: detail, waited: waited, source: source), month: String(ts.prefix(7)))
    }

    private static func append(_ e: Entry, month: String) {
        guard var line = try? encoder.encode(e) else { return }
        line.append(0x0A)
        let url = dir.appendingPathComponent("log-\(month).jsonl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    static func selfTest() {
        let saved = dir, fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("byde-log-test-\(UUID().uuidString)")
        defer { dir = saved }
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        append(Entry(ts: "2026-10-31T09:00:00Z", event: "a"), month: "2026-10")
        append(Entry(ts: "2026-11-02T09:00:00Z", event: "b"), month: "2026-11")
        append(Entry(ts: "2026-11-03T09:00:00Z", event: "c"), month: "2026-11")
        func lines(_ name: String) -> Int {
            ((try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? "").split(separator: "\n").count
        }
        precondition(lines("log-2026-10.jsonl") == 1 && lines("log-2026-11.jsonl") == 2, "entries go to their month's file")
        add("x"); add("y", detail: "d")
        let month = String(stamp.string(from: Date()).prefix(7))
        precondition(lines("log-\(month).jsonl") >= 2, "add appends to this month's file")
        print("log selftest ok")
    }
}
