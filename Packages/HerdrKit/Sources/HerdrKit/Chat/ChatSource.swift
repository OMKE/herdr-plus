import Foundation

public struct ExecResult: Sendable {
    public var code: Int
    public var stdout: Data
    public var stderr: Data
    public var timedOut: Bool
    public var text: String { String(decoding: stdout, as: UTF8.self) }
}

extension CoreConnection {
    public func exec(_ argv: [String], on machine: String? = nil, timeout: Duration = .seconds(20)) async throws -> ExecResult {
        var params: [String: JSONValue] = ["argv": .array(argv.map { .string($0) })]
        if let machine { params["on"] = .string(machine) }
        let r = try await call("machine.exec", .object(params), timeout: timeout)
        let out = r["stdout"]?.string.flatMap { Data(base64Encoded: $0) } ?? Data()
        let err = r["stderr"]?.string.flatMap { Data(base64Encoded: $0) } ?? Data()
        return ExecResult(code: r["code"]?.int ?? -1, stdout: out, stderr: err, timedOut: r["timed_out"]?.bool ?? false)
    }

    public func shell(_ script: String, _ args: [String] = [], on machine: String? = nil, timeout: Duration = .seconds(20)) async throws -> ExecResult {
        try await exec(["sh", "-c", script, "sh"] + args, on: machine, timeout: timeout)
    }

    public func screen(terminal: String) async throws -> String {
        let r = try await call("terminal.read", ["terminal": .string(terminal)])
        return r["text"]?.string ?? ""
    }

    public func keys(terminal: String, _ keys: [String]) async throws {
        _ = try await call("terminal.keys", ["terminal": .string(terminal), "keys": .array(keys.map { .string($0) })], timeout: .seconds(75))
    }

    public func put(terminal: String, name: String, data: Data) async throws -> String {
        let r = try await call("terminal.put", ["terminal": .string(terminal), "name": .string(name), "data": .string(data.base64EncodedString())], timeout: .seconds(60))
        return r["path"]?.string ?? ""
    }
}

public struct AgentLog: Sendable, Hashable {
    public enum Kind: String, Sendable { case claude, codex }
    public var kind: Kind
    public var path: String
    public var dir: String?
    public var machine: String?
    public var pid: Int?

    public init(kind: Kind, path: String, dir: String?, machine: String?, pid: Int? = nil) {
        self.kind = kind
        self.path = path
        self.dir = dir
        self.machine = machine
        self.pid = pid
    }
}

public enum Locator {
    struct Proc { var pid: Int; var ppid: Int; var start: Date?; var command: String }

    static let wrappers: Set<String> = ["node", "bun", "deno", "python", "python3", "env", "npx", "bunx", "sh", "bash", "zsh"]

    static func base(_ s: String) -> String {
        String(s.split(separator: "/").last ?? Substring(s))
    }

    static func program(_ argv: [String]) -> String? {
        for a in argv {
            let b = base(a)
            if a.hasPrefix("-") || b.contains("=") { continue }
            if wrappers.contains(b) || b.hasPrefix("python") || b.hasPrefix("node") { continue }
            return b
        }
        return nil
    }

    static func kind(of program: String?) -> AgentLog.Kind? {
        guard let p = program?.lowercased() else { return nil }
        if p == "claude" || p.hasPrefix("claude-") || p == "cli.js" { return .claude }
        if p == "codex" || p.hasPrefix("codex-") { return .codex }
        return nil
    }

    public static func agentKind(_ t: Terminal) -> AgentLog.Kind? {
        if let app = t.status?.app?.lowercased() {
            if app.contains("claude") { return .claude }
            if app.contains("codex") { return .codex }
        }
        if let fg = t.foreground {
            if let k = kind(of: fg.name) { return k }
            if let a = fg.argv, let k = kind(of: program(a)) { return k }
        }
        return kind(of: program(t.argv))
    }

    static let lstart: DateFormatter = {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return d
    }()

    static func parseStart(_ s: String) -> Date? {
        lstart.date(from: s.split(whereSeparator: \.isWhitespace).joined(separator: " "))
    }

    static func parsePS(_ text: String) -> [Int: Proc] {
        var out: [Int: Proc] = [:]
        for line in text.split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            guard f.count >= 8, let pid = Int(f[0]), let ppid = Int(f[1]) else { continue }
            let start = parseStart(f[2...6].joined(separator: " "))
            out[pid] = Proc(pid: pid, ppid: ppid, start: start, command: f[7].trimmingCharacters(in: .whitespaces))
        }
        return out
    }

    static func descendants(of root: Int, in procs: [Int: Proc]) -> [Proc] {
        var children: [Int: [Proc]] = [:]
        for p in procs.values { children[p.ppid, default: []].append(p) }
        var out: [Proc] = []
        var stack = [root]
        var seen: Set<Int> = []
        while let n = stack.popLast(), out.count < 512 {
            for c in children[n] ?? [] where seen.insert(c.pid).inserted {
                out.append(c)
                stack.append(c.pid)
            }
        }
        return out
    }

    static func isKind(_ p: Proc, _ k: AgentLog.Kind) -> Bool {
        kind(of: program(p.command.split(separator: " ", omittingEmptySubsequences: true).map(String.init))) == k
    }

    static let claudeScript = #"""
    for p in "$@"; do
      d=""
      if [ -r "/proc/$p/environ" ]; then
        d=$(tr '\0' '\n' < "/proc/$p/environ" | sed -n 's/^CLAUDE_CONFIG_DIR=//p' | head -n 1)
      else
        d=$(ps -E -ww -o command= -p "$p" 2>/dev/null | tr ' ' '\n' | sed -n 's/^CLAUDE_CONFIG_DIR=//p' | head -n 1)
      fi
      [ -n "$d" ] || d="$HOME/.claude"
      case "$d" in "~/"*) d="$HOME/${d#\~/}";; esac
      printf 'PID %s\nDIR %s\n' "$p" "$d"
      if [ -r "$d/sessions/$p.json" ]; then printf 'JSON '; tr '\n' ' ' < "$d/sessions/$p.json"; printf '\n'; fi
    done
    """#

    static let findScript = #"""
    d="$1"; s="$2"
    for f in "$d"/projects/*/"$s".jsonl; do [ -f "$f" ] && printf '%s\n' "$f"; done
    """#

    public static func locate(_ t: Terminal, via core: CoreConnection) async throws -> AgentLog? {
        guard let kind = agentKind(t) else { return nil }
        let machine = t.machine
        let ps = try await core.exec(["ps", "-A", "-ww", "-o", "pid=,ppid=,lstart=,command="], on: machine)
        let procs = parsePS(ps.text)
        let roots = [t.foreground?.pid, t.pid].compactMap { $0 }
        guard !roots.isEmpty else { return nil }
        switch kind {
        case .claude:
            var cands = roots.filter { procs[$0].map { isKind($0, .claude) } ?? false }
            if cands.isEmpty, let root = t.pid ?? roots.first {
                cands = descendants(of: root, in: procs).filter { isKind($0, .claude) }
                    .sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }.map(\.pid)
            }
            var seen: Set<Int> = []
            cands = cands.filter { seen.insert($0).inserted }
            guard !cands.isEmpty else { return nil }
            let r = try await core.shell(claudeScript, cands.map(String.init), on: machine)
            var hits: [(sid: String, dir: String, pid: Int)] = []
            var pid = 0, dir = ""
            for line in r.text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("PID ") { pid = Int(line.dropFirst(4)) ?? 0 }
                else if line.hasPrefix("DIR ") { dir = String(line.dropFirst(4)) }
                else if line.hasPrefix("JSON "), let sid = sessionId(String(line.dropFirst(5)), pid: pid, start: procs[pid]?.start) {
                    hits.append((sid, dir, pid))
                }
            }
            let sids = Set(hits.map(\.sid))
            guard sids.count == 1, let hit = hits.first else { return nil }
            guard let path = try await find(sid: hit.sid, dir: hit.dir, via: core, on: machine) else { return nil }
            return AgentLog(kind: .claude, path: path, dir: hit.dir, machine: machine, pid: hit.pid)
        case .codex:
            var pids = Set(roots)
            for r in roots { for d in descendants(of: r, in: procs) { pids.insert(d.pid) } }
            let r = try await core.exec(["lsof", "-nP", "-Fn", "-p", pids.sorted().map(String.init).joined(separator: ",")], on: machine)
            let files = Set(r.text.split(separator: "\n").filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
                .filter { $0.hasSuffix(".jsonl") && $0.contains("/sessions/") && base($0).hasPrefix("rollout-") })
            guard files.count == 1, let path = files.first else { return nil }
            return AgentLog(kind: .codex, path: path, dir: nil, machine: machine)
        }
    }

    public static func find(sid: String, dir: String, via core: CoreConnection, on machine: String?) async throws -> String? {
        guard isSessionId(sid) else { return nil }
        let r = try await core.shell(findScript, [dir, sid], on: machine)
        let paths = r.text.split(separator: "\n").map(String.init)
        return paths.count == 1 ? paths[0] : nil
    }

    static func isSessionId(_ s: String) -> Bool {
        s.wholeMatch(of: /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) != nil
    }

    static func sessionId(_ json: String, pid: Int, start: Date?) -> String? {
        guard let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let sid = o["sessionId"] as? String, isSessionId(sid) else { return nil }
        if let p = o["pid"] as? Int, p != pid { return nil }
        if let s = o["procStart"] as? String, let ps = parseStart(s), let start, !sameStart(ps, start) { return nil }
        return sid
    }

    static func sameStart(_ a: Date, _ b: Date) -> Bool {
        let d = abs(a.timeIntervalSince(b))
        guard d <= 14 * 3600 + 2 else { return false }
        let r = d.truncatingRemainder(dividingBy: 900)
        return r <= 2 || r >= 898
    }
}

public struct LogTail: Sendable {
    public static let firstRead = 2_097_152
    public static let maxRead = 4_194_304
    public static let maxTotal = 8_388_608

    public var path: String
    public var offset: Int = -1
    public var total = 0
    public var start = -1
    public var parser = ConversationParser()

    public init(path: String) { self.path = path }

    static let rangeScript = #"""
    f="$1"; from="$2"; n="$3"
    [ -r "$f" ] || exit 3
    tail -c +"$((from + 1))" "$f" | head -c "$n"
    """#

    public static func earlier(path: String, before end: Int, bytes: Int = maxRead, via core: CoreConnection, on machine: String?) async throws -> (parser: ConversationParser, start: Int) {
        let from = max(0, end - bytes)
        guard end > from else { return (ConversationParser(), from) }
        let r = try await core.shell(rangeScript, [path, String(from), String(end - from)], on: machine, timeout: .seconds(40))
        guard r.code == 0 else { throw CoreError.disconnected }
        var body = r.stdout[...]
        var at = from
        if from > 0, let cut = body.firstIndex(of: 0x0A) {
            at += body.distance(from: body.startIndex, to: cut) + 1
            body = body[(cut + 1)...]
        }
        var p = ConversationParser()
        for line in body.split(separator: 0x0A) {
            p.feed(line: String(decoding: line, as: UTF8.self))
        }
        return (p, at)
    }

    static let script = #"""
    f="$1"; off="$2"; first="$3"; max="$4"
    [ -r "$f" ] || exit 3
    sz=$(wc -c < "$f" | tr -d ' ')
    if [ "$off" -lt 0 ]; then
      if [ "$sz" -gt "$first" ]; then off=$((sz - first)); else off=0; fi
    fi
    printf '%s %s\n' "$sz" "$off"
    if [ "$off" -lt "$sz" ]; then tail -c +"$((off + 1))" "$f" | head -c "$max"; fi
    """#

    public mutating func poll(via core: CoreConnection, on machine: String?) async throws -> Bool {
        let r = try await core.shell(Self.script, [path, String(offset), String(Self.firstRead), String(Self.maxRead)], on: machine, timeout: .seconds(30))
        guard r.code == 0, let nl = r.stdout.firstIndex(of: 0x0A) else { throw CoreError.disconnected }
        let head = String(decoding: r.stdout[r.stdout.startIndex..<nl], as: UTF8.self).split(separator: " ")
        guard head.count == 2, let size = Int(head[0]), let start = Int(head[1]) else { return false }
        if offset >= 0, size < offset {
            self = LogTail(path: path)
            return try await poll(via: core, on: machine)
        }
        var body = r.stdout[(nl + 1)...]
        let first = offset < 0
        var at = start
        if first, start > 0, let cut = body.firstIndex(of: 0x0A) {
            at += body.distance(from: body.startIndex, to: cut) + 1
            body = body[(cut + 1)...]
        }
        if first { self.start = at }
        guard let last = body.lastIndex(of: 0x0A) else {
            if first { offset = at }
            return first
        }
        let chunk = body[body.startIndex...last]
        at += chunk.count
        offset = at
        total += chunk.count
        if total > Self.maxTotal {
            self = LogTail(path: path)
            return try await poll(via: core, on: machine)
        }
        for line in chunk.split(separator: 0x0A) {
            parser.feed(line: String(decoding: line, as: UTF8.self))
        }
        return true
    }
}
