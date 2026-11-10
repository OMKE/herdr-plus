import Foundation

public enum ChatRows {
    static let gap: TimeInterval = 900
    static let textCap = 20000
    static let outputCap = 400

    public static func build(_ items: [ChatItem], now: Date = Date(), calendar: Calendar = .current) -> [ChatRow] {
        var out: [ChatRow] = []
        var lastTime: Date?
        var turnStart: Date?
        var turnEnd: Date?
        var turnTools = 0
        var turnHasAssistant = false
        var turnId = ""
        var pending = false

        func closeTurn() {
            if turnHasAssistant, let s = turnStart, let e = turnEnd {
                out.append(ChatRow(id: "footer-\(turnId)", kind: .footer(footer(start: s, end: e, tools: turnTools, calendar: calendar)), timestamp: e))
            }
            turnStart = nil; turnEnd = nil; turnTools = 0; turnHasAssistant = false
        }

        for item in items {
            if let t = item.timestamp {
                if let last = lastTime, t.timeIntervalSince(last) >= gap || !calendar.isDate(t, inSameDayAs: last) {
                    out.append(ChatRow(id: "sep-\(item.id)", kind: .separator(label(t, now: now, calendar: calendar)), timestamp: t))
                } else if lastTime == nil {
                    out.append(ChatRow(id: "sep-\(item.id)", kind: .separator(label(t, now: now, calendar: calendar)), timestamp: t))
                }
                lastTime = t
            }
            if case .tools(let chips) = item.kind {
                pending = chips.contains { $0.calls.contains { !$0.isDone } }
            } else if case .status = item.kind {
            } else {
                pending = false
            }
            switch item.kind {
            case .user(let text):
                closeTurn()
                turnId = item.id
                turnStart = item.timestamp
                let note = ConversationParser.hcNote(text)
                out.append(ChatRow(id: item.id, kind: .user(text: cap(note?.text ?? text), from: note?.from), timestamp: item.timestamp, images: item.images, imageKeys: item.imageKeys))
            case .assistant(let text):
                turnHasAssistant = true
                if turnStart == nil { turnStart = item.timestamp; turnId = item.id }
                if let t = item.timestamp { turnEnd = t }
                out.append(ChatRow(id: item.id, kind: .assistant(cap(text)), timestamp: item.timestamp))
            case .tools(let chips):
                if turnStart == nil { turnStart = item.timestamp; turnId = item.id }
                if let t = item.timestamp { turnEnd = max(turnEnd ?? t, t) }
                turnTools += chips.reduce(0) { $0 + max(1, $1.calls.count) }
                let capped = chips.map { c -> ToolChip in
                    var c = c
                    c.calls = c.calls.map { var k = $0; k.output = k.output.map { cap($0, outputCap) }; return k }
                    return c
                }
                if case .tools(let prev)? = out.last?.kind {
                    out[out.count - 1].kind = .tools(merge(prev, capped))
                } else {
                    out.append(ChatRow(id: item.id, kind: .tools(capped), timestamp: item.timestamp))
                }
            case .permission(let p):
                out.append(ChatRow(id: item.id, kind: .permission(p), timestamp: item.timestamp))
            case .question(let q):
                out.append(ChatRow(id: item.id, kind: .question(q), timestamp: item.timestamp))
            case .status(let s):
                out.append(ChatRow(id: item.id, kind: .status(s), timestamp: item.timestamp))
            }
        }
        if !pending { closeTurn() }
        return out
    }

    public static func toolRunning(_ rows: [ChatRow]) -> Bool {
        for r in rows.reversed() {
            switch r.kind {
            case .tools(let chips): return chips.contains { $0.calls.contains { !$0.isDone } }
            case .status, .separator: continue
            default: return false
            }
        }
        return false
    }

    static func merge(_ a: [ToolChip], _ b: [ToolChip]) -> [ToolChip] {
        var out = a
        for c in b {
            if let i = out.firstIndex(where: { $0.symbol == c.symbol && base($0.text) == base(c.text) }) {
                let calls = out[i].calls + c.calls
                out[i].calls = calls
                out[i].text = retext(c.text, count: calls.count)
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func base(_ text: String) -> String {
        text.replacing(/\d+/, with: "#")
    }

    static func retext(_ text: String, count: Int) -> String {
        let singularToPlural: [String: String] = [
            "Read a file": "Read %d files", "Edited a file": "Edited %d files", "Wrote a file": "Wrote %d files",
            "Ran a command": "Ran %d commands", "Searched the code": "Searched the code %d times",
            "Searched the web": "Searched the web %d times", "Delegated a task": "Delegated %d tasks",
            "Used a connector": "Used connectors %d times", "Edited files": "Edited files %d times",
        ]
        if count <= 1 { return text }
        if let p = singularToPlural[text] { return String(format: p, count) }
        if text.firstMatch(of: /\d+/) != nil { return text.replacing(/\d+/, with: "\(count)") }
        return text
    }

    static func cap(_ s: String, _ n: Int = textCap) -> String {
        s.count > n ? String(s.prefix(n)) + "…" : s
    }

    static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = f
        return d
    }

    static func label(_ t: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(t, inSameDayAs: now) { return formatter("HH:mm").string(from: t) }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(t, inSameDayAs: y) {
            return "Yesterday " + formatter("HH:mm").string(from: t)
        }
        return formatter("EEE d MMM HH:mm").string(from: t)
    }

    static func footer(start: Date, end: Date, tools: Int, calendar: Calendar) -> String {
        var parts = [formatter("HH:mm").string(from: end)]
        let secs = Int(max(0, end.timeIntervalSince(start)))
        if secs > 0 { parts.append("Worked " + duration(secs)) }
        if tools > 0 { parts.append(tools == 1 ? "1 tool" : "\(tools) tools") }
        return parts.joined(separator: " · ")
    }

    static func duration(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60)m" : "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}
