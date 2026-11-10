import Foundation

public struct TerminalStore: Sendable {
    public private(set) var terminals: [String: Terminal] = [:]
    public private(set) var order: [String] = []
    public private(set) var seq: UInt64 = 0

    public init() {}

    public var all: [Terminal] { order.compactMap { terminals[$0] } }

    public subscript(address: String) -> Terminal? { terminals[address] }

    public mutating func reset(seq: UInt64, terminals list: [Terminal]) {
        self.seq = seq
        terminals = [:]
        order = []
        for t in list { upsert(t) }
    }

    private mutating func upsert(_ t: Terminal) {
        if terminals[t.address] == nil { order.append(t.address) }
        terminals[t.address] = t
    }

    private mutating func remove(_ address: String) {
        terminals[address] = nil
        order.removeAll { $0 == address }
    }

    @discardableResult
    public mutating func apply(_ event: TerminalEvent) -> Bool {
        if event.seq != 0, event.seq <= seq, seq != 0 { return false }
        if event.seq != 0 { seq = event.seq }
        guard let address = event.terminal else { return true }
        let d = event.data
        switch event.type {
        case "created", "restarted":
            upsert(Terminal(json: d))
        case "removed":
            remove(address)
        default:
            guard var t = terminals[address] else { return true }
            switch event.type {
            case "lost":
                t.reason = d["reason"]?.string
                t.exitCode = d["exit_code"]?.int
                t.foreground = nil
            case "finished":
                t.state = "finished"
                t.reason = d["reason"]?.string
                t.exitCode = d["exit_code"]?.int
                t.finishedMs = d["finished_ms"]?.double.map { UInt64($0) }
                t.foreground = nil
            case "keep":
                t.keep = d["keep"]?.bool ?? t.keep
            case "status":
                let s = d["status"]
                t.status = (s == nil || s!.isNull) ? nil : try? s!.decode(Status.self)
                t.reported = d["reported"]?.bool ?? t.reported
                t.statusMs = UInt64(Date().timeIntervalSince1970 * 1000)
            case "turn":
                t.turn = d["turn"]?.int ?? t.turn
            case "title":
                t.title = d["title"]?.string ?? t.title
            case "labels":
                if let labels = d["labels"]?.object { t.labels = labels.compactMapValues(\.string) }
            case "size":
                t.cols = d["cols"]?.int ?? t.cols
                t.rows = d["rows"]?.int ?? t.rows
            case "foreground":
                t.foreground = (d.isNull) ? nil : try? d.decode(Foreground.self)
            default:
                break
            }
            terminals[address] = t
        }
        return true
    }
}
