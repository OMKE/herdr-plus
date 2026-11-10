import Foundation

public struct NotifyConfig: Codable, Sendable {
    public var server: String
    public var topic: String
    public var token: String?
    public var states: [String]
    public var debounceSeconds: Double
    public var hc: String?

    public init(server: String = "https://ntfy.sh", topic: String, token: String? = nil, states: [String] = ["blocked", "done", "error"], debounceSeconds: Double = 3, hc: String? = nil) {
        self.server = server
        self.topic = topic
        self.token = token
        self.states = states
        self.debounceSeconds = debounceSeconds
        self.hc = hc
    }

    enum CodingKeys: String, CodingKey { case server, topic, token, states, debounceSeconds = "debounce_seconds", hc }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? "https://ntfy.sh"
        topic = try c.decode(String.self, forKey: .topic)
        token = try c.decodeIfPresent(String.self, forKey: .token)
        states = try c.decodeIfPresent([String].self, forKey: .states) ?? ["blocked", "done", "error"]
        debounceSeconds = try c.decodeIfPresent(Double.self, forKey: .debounceSeconds) ?? 3
        hc = try c.decodeIfPresent(String.self, forKey: .hc)
    }
}

public struct AgentNotification: Sendable, Equatable {
    public var title: String
    public var body: String
    public var click: String
    public var priority: Int
    public var tags: [String]

    public init(title: String, body: String, click: String, priority: Int, tags: [String]) {
        self.title = title
        self.body = body
        self.click = click
        self.priority = priority
        self.tags = tags
    }
}

public enum NotificationText {
    public static func truncate(_ s: String, limit: Int = 140) -> String {
        let collapsed = s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    public static func clickURL(for address: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return "herdr-ios://terminal/" + (address.addingPercentEncoding(withAllowedCharacters: allowed) ?? address)
    }

    public static func question(fromScreen text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        let meaningful = lines.filter { l in
            !l.isEmpty && l.contains(where: { $0.isLetter }) && !l.allSatisfy({ "─━═│┃╭╮╯╰-_=".contains($0) || $0 == " " })
        }
        return meaningful.suffix(4).joined(separator: " ")
    }

    public static func make(terminal: Terminal, spaces: [Space], programs: Programs, screen: String?) -> AgentNotification {
        let app = programs.displayName(for: terminal)
        var place: String?
        for s in spaces {
            for tab in s.tabs where tab.terminals.contains(where: { LayoutDocument.address($0, machine: s.machine) == terminal.address }) {
                place = s.displayName
            }
        }
        if place == nil, !terminal.cwd.isEmpty { place = (terminal.cwd as NSString).lastPathComponent }
        let title = place.map { "\(app) · \($0)" } ?? app
        let state = terminal.agentState
        var body = terminal.status?.msg ?? ""
        if body.isEmpty, let screen { body = question(fromScreen: screen) }
        if body.isEmpty {
            switch state {
            case .blocked: body = "Waiting for you"
            case .done: body = "Finished"
            case .error: body = "Hit an error"
            default: body = state.rawValue
            }
        }
        return AgentNotification(
            title: title,
            body: truncate(body),
            click: clickURL(for: terminal.address),
            priority: state == .blocked ? 4 : 3,
            tags: [state == .blocked ? "hourglass" : state == .error ? "warning" : "white_check_mark"]
        )
    }
}

public enum Ntfy {
    public static func post(_ n: AgentNotification, config: NotifyConfig) async throws {
        guard var url = URL(string: config.server) else { throw CoreError.badResponse("bad server url") }
        url.appendPathComponent(config.topic)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(n.body.utf8)
        req.setValue(rfc2047(n.title), forHTTPHeaderField: "Title")
        req.setValue(n.click, forHTTPHeaderField: "Click")
        req.setValue(String(n.priority), forHTTPHeaderField: "Priority")
        req.setValue(n.tags.joined(separator: ","), forHTTPHeaderField: "Tags")
        if let token = config.token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw CoreError.badResponse("ntfy HTTP \(h.statusCode)")
        }
    }

    static func rfc2047(_ s: String) -> String {
        if s.allSatisfy({ $0.isASCII }) { return s }
        return "=?UTF-8?B?" + Data(s.utf8).base64EncodedString() + "?="
    }
}

public actor NotifyEngine {
    private var store = TerminalStore()
    private var spaces: [Space] = []
    private var lastSent: [String: AgentState] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private let config: NotifyConfig
    private let programs = Programs.bundled
    private let sink: @Sendable (AgentNotification) async -> Void
    private let log: @Sendable (String) -> Void

    public init(config: NotifyConfig, log: @escaping @Sendable (String) -> Void = { print($0) }, sink: @escaping @Sendable (AgentNotification) async -> Void) {
        self.config = config
        self.sink = sink
        self.log = log
    }

    public func run(connection: CoreConnection) async throws {
        _ = try await connection.start()
        await refreshSpaces(connection)
        let sub = try await connection.subscribeEvents()
        store.reset(seq: sub.seq, terminals: sub.terminals)
        for t in store.all { lastSent[t.address] = t.agentState }
        log("watching \(store.all.count) terminals")
        for await n in sub.stream {
            switch n {
            case .event(let e):
                if e.type == "doc" {
                    await refreshSpaces(connection)
                    continue
                }
                let before = e.terminal.flatMap { store[$0]?.agentState }
                store.apply(e)
                guard e.type == "status", let addr = e.terminal, let t = store[addr] else { continue }
                if t.agentState != before { schedule(addr, connection: connection) }
            case .missed(let seq, let terminals):
                store.reset(seq: seq, terminals: terminals)
            case .heartbeat:
                break
            }
        }
        throw CoreError.disconnected
    }

    private func refreshSpaces(_ c: CoreConnection) async {
        var all: [Space] = []
        if let local = try? await c.layout() { all += local.spaces }
        if let machines = try? await c.machines() {
            for m in machines where m.isConnected && !m.temporary {
                if let d = try? await c.layout(on: m.name) { all += d.spaces }
            }
        }
        spaces = all
    }

    private func schedule(_ addr: String, connection: CoreConnection) {
        timers[addr]?.cancel()
        let delay = config.debounceSeconds
        timers[addr] = Task {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            await self.fire(addr, connection: connection)
        }
    }

    private func fire(_ addr: String, connection: CoreConnection) async {
        timers[addr] = nil
        guard let t = store[addr] else { return }
        let state = t.agentState
        defer { lastSent[addr] = state }
        guard config.states.contains(state.rawValue), lastSent[addr] != state else { return }
        var screen: String?
        if (t.status?.msg ?? "").isEmpty { screen = try? await connection.read(terminal: addr, lines: 30) }
        let n = NotificationText.make(terminal: t, spaces: spaces, programs: programs, screen: screen)
        log("notify \(addr) \(state.rawValue): \(n.title) — \(n.body)")
        await sink(n)
    }
}
