import Foundation

public indirect enum PaneContent: Sendable, Hashable {
    case terminal(String)
    case mod(String, JSONValue)
    case reference(tab: String, pane: String)
    case agent(String)
    case empty

    init(json: JSONValue?) {
        guard let json else { self = .empty; return }
        if let t = json["terminal"]?.string { self = .terminal(t); return }
        if let m = json["mod"]?.string { self = .mod(m, json["props"] ?? .null); return }
        if let tab = json["tab"]?.string, let pane = json["pane"]?.string { self = .reference(tab: tab, pane: pane); return }
        if let a = json["agent"]?.string { self = .agent(a); return }
        self = .empty
    }
}

public struct LayoutNode: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case row, column, stack, block }

    public var id: String
    public var kind: Kind
    public var children: [LayoutNode]
    public var content: PaneContent
    public var weight: Double?
    public var px: Double?
    public var active: Int?

    public init(json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        let type = json["type"]?.string
        let legacyBlock = json["block"]
        if let type, let k = Kind(rawValue: type) {
            kind = k
        } else if legacyBlock != nil {
            kind = .block
        } else {
            kind = (json["children"] != nil) ? .row : .block
        }
        children = (json["children"]?.array ?? []).map(LayoutNode.init(json:))
        content = PaneContent(json: json["content"] ?? legacyBlock)
        weight = json["size"]?["weight"]?.double
        px = json["size"]?["px"]?.double
        active = json["active"]?.int
    }

    public var leaves: [LayoutNode] {
        kind == .block ? [self] : children.flatMap(\.leaves)
    }

    public var terminals: [String] {
        leaves.compactMap { if case .terminal(let t) = $0.content { t } else { nil } }
    }
}

public struct SpaceTab: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var root: LayoutNode
    public var floating: [LayoutNode]

    public init(json: JSONValue) {
        id = json["id"]?.string ?? UUID().uuidString
        name = json["name"]?.string ?? ""
        root = LayoutNode(json: json["root"] ?? .object([:]))
        floating = (json["floating"]?.array ?? []).map { LayoutNode(json: $0["root"] ?? $0) }
    }

    public var panes: [LayoutNode] { root.leaves + floating.flatMap(\.leaves) }
    public var terminals: [String] { panes.compactMap { if case .terminal(let t) = $0.content { t } else { nil } } }
}

public struct Space: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var folder: String
    public var color: String?
    public var tabs: [SpaceTab]
    public var machine: String?

    public init(json: JSONValue, machine: String? = nil) {
        id = json["id"]?.string ?? UUID().uuidString
        name = json["name"]?.string ?? ""
        folder = json["folder"]?.string ?? ""
        color = json["color"]?.string
        tabs = (json["tabs"]?.array ?? []).map(SpaceTab.init(json:))
        self.machine = machine
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let base = (folder as NSString).lastPathComponent
        return base.isEmpty ? "space" : base
    }

    public var monogram: String {
        let words = displayName.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(displayName.prefix(2)).uppercased()
    }

    public var uid: String { (machine ?? "") + "/" + id }
}

public struct LayoutDocument: Sendable, Hashable {
    public var spaces: [Space]
    public var version: Int

    public init(spaces: [Space] = [], version: Int = 0) {
        self.spaces = spaces
        self.version = version
    }

    public init(value: JSONValue, version: Int, machine: String? = nil) {
        spaces = (value["spaces"]?.array ?? []).map { Space(json: $0, machine: machine) }
        self.version = version
    }

    public static func address(_ terminal: String, machine: String?) -> String {
        guard let machine, !machine.isEmpty else { return terminal }
        return machine + "/" + terminal
    }
}

public struct AgentEntry: Sendable, Hashable, Identifiable {
    public var terminal: Terminal
    public var space: Space?
    public var tab: SpaceTab?
    public var paneIndex: Int
    public var isWorker: Bool

    public var id: String { terminal.address }
}

public enum AgentOrdering {
    public static func entries(spaces: [Space], terminals: [Terminal]) -> [AgentEntry] {
        let byAddress = Dictionary(terminals.map { ($0.address, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [AgentEntry] = []
        for space in spaces {
            for tab in space.tabs {
                for (i, local) in tab.terminals.enumerated() {
                    let addr = LayoutDocument.address(local, machine: space.machine)
                    guard let t = byAddress[addr], t.isAgent, !seen.contains(addr) else { continue }
                    seen.insert(addr)
                    out.append(AgentEntry(terminal: t, space: space, tab: tab, paneIndex: i, isWorker: false))
                    for w in terminals where w.parent == addr && w.isAgent && !seen.contains(w.address) {
                        seen.insert(w.address)
                        out.append(AgentEntry(terminal: w, space: space, tab: tab, paneIndex: i, isWorker: true))
                    }
                }
            }
        }
        for t in terminals where t.isAgent && t.isLive && !seen.contains(t.address) {
            seen.insert(t.address)
            out.append(AgentEntry(terminal: t, space: nil, tab: nil, paneIndex: 0, isWorker: t.parent != nil))
        }
        return out
    }

    public static func needsYou(_ entries: [AgentEntry]) -> [AgentEntry] {
        entries.filter { $0.terminal.agentState == .blocked || $0.terminal.agentState == .error }
    }
}
