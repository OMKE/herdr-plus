import Foundation

public enum AgentState: String, Sendable, Comparable {
    case blocked, error, working, done, idle, unknown

    public init(word: String?) {
        guard let word else { self = .unknown; return }
        self = AgentState(rawValue: word) ?? .unknown
    }

    var urgency: Int {
        switch self {
        case .blocked: 0
        case .error: 1
        case .done: 2
        case .working: 3
        case .idle: 4
        case .unknown: 5
        }
    }

    public static func < (a: AgentState, b: AgentState) -> Bool { a.urgency < b.urgency }
}

public struct Status: Sendable, Hashable, Codable {
    public var state: String
    public var kind: String?
    public var progress: Int?
    public var app: String?
    public var title: String?
    public var msg: String?

    public init(state: String, kind: String? = nil, progress: Int? = nil, app: String? = nil, title: String? = nil, msg: String? = nil) {
        self.state = state
        self.kind = kind
        self.progress = progress
        self.app = app
        self.title = title
        self.msg = msg
    }

    public var agentState: AgentState { AgentState(word: state) }
}

public struct Foreground: Sendable, Hashable, Codable {
    public var pid: Int?
    public var name: String?
    public var argv: [String]?
    public var cwd: String?
}

public struct Terminal: Sendable, Hashable, Identifiable {
    public var address: String
    public var name: String?
    public var argv: [String]
    public var cwd: String
    public var cols: Int
    public var rows: Int
    public var title: String
    public var state: String
    public var status: Status?
    public var statusMs: UInt64?
    public var reported: Bool
    public var foreground: Foreground?
    public var labels: [String: String]
    public var parent: String?
    public var createdMs: UInt64
    public var finishedMs: UInt64?
    public var reason: String?
    public var exitCode: Int?
    public var turn: Int
    public var keep: Bool
    public var pid: Int?

    public var id: String { address }
    public var isLive: Bool { state == "live" }
    public var isAgent: Bool { reported || status != nil }
    public var agentState: AgentState { status?.agentState ?? (reported ? .idle : .unknown) }

    public var machine: String? {
        guard let slash = address.lastIndex(of: "/") else { return nil }
        return String(address[address.startIndex..<slash])
    }

    public var localAddress: String {
        guard let slash = address.lastIndex(of: "/") else { return address }
        return String(address[address.index(after: slash)...])
    }

    public init(address: String, argv: [String] = [], cwd: String = "", title: String = "", state: String = "live", status: Status? = nil) {
        self.address = address
        self.name = nil
        self.argv = argv
        self.cwd = cwd
        self.cols = 80
        self.rows = 24
        self.title = title
        self.state = state
        self.status = status
        self.statusMs = nil
        self.reported = status != nil
        self.foreground = nil
        self.labels = [:]
        self.parent = nil
        self.createdMs = 0
        self.finishedMs = nil
        self.reason = nil
        self.exitCode = nil
        self.turn = 0
        self.keep = false
        self.pid = nil
    }

    public init(json: JSONValue) {
        address = json["address"]?.string ?? ""
        name = json["name"]?.string
        argv = json["argv"]?.array?.compactMap(\.string) ?? []
        cwd = json["cwd"]?.string ?? ""
        cols = json["cols"]?.int ?? 80
        rows = json["rows"]?.int ?? 24
        title = json["title"]?.string ?? ""
        state = json["state"]?.string ?? "live"
        status = (json["status"].flatMap { $0.isNull ? nil : $0 }).flatMap { try? $0.decode(Status.self) }
        statusMs = json["status_ms"]?.double.map { UInt64($0) }
        reported = json["reported"]?.bool ?? false
        foreground = (json["foreground"].flatMap { $0.isNull ? nil : $0 }).flatMap { try? $0.decode(Foreground.self) }
        labels = (json["labels"]?.object ?? [:]).compactMapValues(\.string)
        parent = json["parent"]?.string
        createdMs = json["created_ms"]?.double.map { UInt64($0) } ?? 0
        finishedMs = json["finished_ms"]?.double.map { UInt64($0) }
        reason = json["reason"]?.string
        exitCode = json["exit_code"]?.int
        turn = json["turn"]?.int ?? 0
        keep = json["keep"]?.bool ?? false
        pid = json["pid"]?.int
    }
}

public struct Machine: Sendable, Hashable, Identifiable {
    public var name: String
    public var host: String
    public var state: String?
    public var temporary: Bool
    public var version: String?

    public var id: String { name }
    public var isConnected: Bool { state == nil || state == "connected" }

    public init(name: String, host: String = "", state: String? = "connected", temporary: Bool = false, version: String? = nil) {
        self.name = name
        self.host = host
        self.state = state
        self.temporary = temporary
        self.version = version
    }

    public init(json: JSONValue) {
        name = json["name"]?.string ?? ""
        host = json["host"]?.string ?? ""
        state = json["state"]?.string
        temporary = json["temporary"]?.bool ?? false
        version = json["version"]?.string
    }
}

public struct CoreInfo: Sendable, Hashable {
    public var id: String
    public var name: String
    public var version: String
    public var generation: Int
    public var features: [String]
}

public struct TerminalEvent: Sendable {
    public var seq: UInt64
    public var type: String
    public var terminal: String?
    public var machine: String?
    public var data: JSONValue

    public init(seq: UInt64, type: String, terminal: String?, machine: String? = nil, data: JSONValue) {
        self.seq = seq
        self.type = type
        self.terminal = terminal
        self.machine = machine
        self.data = data
    }
}

public enum CoreNotification: Sendable {
    case event(TerminalEvent)
    case heartbeat(seq: UInt64)
    case missed(seq: UInt64, terminals: [Terminal])

    public static func parse(_ json: JSONValue) -> CoreNotification? {
        guard let method = json["method"]?.string else { return nil }
        let params = json["params"] ?? .null
        let seq = UInt64(params["seq"]?.double ?? 0)
        switch method {
        case "event":
            return .event(TerminalEvent(seq: seq, type: params["type"]?.string ?? "", terminal: params["terminal"]?.string, machine: params["machine"]?.string, data: params["data"] ?? .null))
        case "heartbeat":
            return .heartbeat(seq: seq)
        case "missed":
            return .missed(seq: seq, terminals: (params["terminals"]?.array ?? []).map(Terminal.init(json:)))
        default:
            return nil
        }
    }
}
