import Foundation

public struct UsageLimit: Sendable, Hashable {
    public var percent: Double
    public var resetsAt: Date?

    public init(percent: Double, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public struct AgentUsage: Sendable, Hashable {
    public var pid: Int?
    public var account: String?
    public var configDir: String?
    public var model: String?
    public var contextPercent: Double?
    public var contextTokens: Int?
    public var contextSize: Int?
    public var fiveHour: UsageLimit?
    public var sevenDay: UsageLimit?
    public var cost: Double?
    public var updated: Date?

    public init() {}

    public static func parse(_ json: Data) -> AgentUsage? {
        guard let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        var u = AgentUsage()
        u.pid = o["pid"] as? Int
        u.account = (o["account"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        u.configDir = o["config_dir"] as? String
        u.model = (o["model"] as? [String: Any])?["display_name"] as? String
        if let cw = o["context_window"] as? [String: Any] {
            u.contextPercent = number(cw["used_percentage"])
            u.contextSize = number(cw["context_window_size"]).map { Int($0) }
            if let cur = cw["current_usage"] as? [String: Any] {
                let parts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { number(cur[$0]) }
                if !parts.isEmpty { u.contextTokens = Int(parts.reduce(0, +)) }
            }
        }
        if let rl = o["rate_limits"] as? [String: Any] {
            u.fiveHour = limit(rl["five_hour"])
            u.sevenDay = limit(rl["seven_day"])
        }
        u.cost = number((o["cost"] as? [String: Any])?["total_cost_usd"])
        if let ts = o["timestamp"] as? String { u.updated = ISO8601DateFormatter().date(from: ts) }
        return u
    }

    static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d.isFinite ? d : nil }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    static func limit(_ v: Any?) -> UsageLimit? {
        guard let o = v as? [String: Any], let p = number(o["used_percentage"]) else { return nil }
        let reset = number(o["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return UsageLimit(percent: min(max(p, 0), 100), resetsAt: reset)
    }
}

public struct AccountUsage: Sendable, Hashable, Identifiable {
    public var id: String { account }
    public var account: String
    public var configDir: String?
    public var fiveHour: UsageLimit?
    public var sevenDay: UsageLimit?
    public var updated: Date?
    public var sessions: Int
}

public enum UsageReader {
    static let script = #"""
    d="$HOME/.scape/sessions"
    [ -d "$d" ] || exit 4
    find "$d" -maxdepth 1 -name '*.json' -mtime -8 2>/dev/null | while read -r f; do
      printf '%s\n' "$(tr '\n' ' ' < "$f")"
    done
    """#

    static let oneScript = #"""
    f="$HOME/.scape/sessions/$1.json"
    [ -r "$f" ] && tr '\n' ' ' < "$f"
    """#

    public static func all(via core: CoreConnection, on machine: String? = nil) async throws -> [AgentUsage]? {
        let r = try await core.shell(script, [], on: machine, timeout: .seconds(15))
        if r.code == 4 { return nil }
        return r.text.split(separator: "\n").compactMap { AgentUsage.parse(Data($0.utf8)) }
    }

    public static func session(pid: Int, via core: CoreConnection, on machine: String? = nil) async throws -> AgentUsage? {
        let r = try await core.shell(oneScript, [String(pid)], on: machine, timeout: .seconds(10))
        return AgentUsage.parse(r.stdout)
    }

    public static func accounts(_ all: [AgentUsage], now: Date = Date()) -> [AccountUsage] {
        var by: [String: [AgentUsage]] = [:]
        for u in all { by[u.account ?? u.configDir ?? "Claude", default: []].append(u) }
        return by.map { name, list in
            let sorted = list.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
            func fresh(_ l: UsageLimit?) -> UsageLimit? {
                guard let l else { return nil }
                if let r = l.resetsAt, r < now { return UsageLimit(percent: 0, resetsAt: nil) }
                return l
            }
            let five = sorted.first { $0.fiveHour != nil }?.fiveHour
            let seven = sorted.first { $0.sevenDay != nil }?.sevenDay
            return AccountUsage(account: name, configDir: sorted.first?.configDir, fiveHour: fresh(five), sevenDay: fresh(seven),
                                updated: sorted.first?.updated, sessions: list.count)
        }
        .sorted { $0.account < $1.account }
    }
}
