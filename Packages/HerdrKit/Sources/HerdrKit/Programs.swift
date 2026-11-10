import Foundation

public struct Program: Sendable, Hashable {
    public var key: String
    public var name: String
    public var icon: String?
    public var match: [String]
    public var run: [String]
    public var tint: Bool
    public var tile: String?
    public var color: String?
}

public struct Programs: Sendable {
    public var programs: [String: Program]
    public var shells: Set<String>
    public var interpreters: Set<String>

    public static let bundled: Programs = {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(ProgramsData.json.utf8)) else {
            return Programs(programs: [:], shells: [], interpreters: [])
        }
        return Programs(json: json)
    }()

    public init(programs: [String: Program], shells: Set<String>, interpreters: Set<String>) {
        self.programs = programs
        self.shells = shells
        self.interpreters = interpreters
    }

    public init(json: JSONValue) {
        shells = Set(json["shells"]?.array?.compactMap(\.string) ?? [])
        interpreters = Set(json["interpreters"]?.array?.compactMap(\.string) ?? [])
        var out: [String: Program] = [:]
        for (key, v) in json["programs"]?.object ?? [:] {
            let icon = v["icon"]?.string.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
            out[key] = Program(
                key: key,
                name: v["name"]?.string ?? key,
                icon: icon,
                match: v["match"]?.array?.compactMap(\.string) ?? [],
                run: v["run"]?.array?.compactMap(\.string) ?? [],
                tint: v["tint"]?.bool ?? false,
                tile: v["tile"]?.string,
                color: v["color"]?.string
            )
        }
        programs = out
    }

    public func program(named name: String) -> Program? {
        let n = (name as NSString).lastPathComponent.lowercased()
        if let p = programs[n] { return p }
        return programs.values.first { $0.match.contains(n) || $0.run.first == n }
    }

    public func program(for terminal: Terminal) -> Program? {
        if let app = terminal.status?.app, let p = program(named: app) { return p }
        if let fg = terminal.foreground {
            let argv = fg.argv ?? []
            var candidate = fg.name
            if let first = argv.first {
                let base = (first as NSString).lastPathComponent
                if interpreters.contains(base), argv.count > 1 {
                    candidate = argv.dropFirst().first { !$0.hasPrefix("-") }
                } else {
                    candidate = base
                }
            }
            if let c = candidate, !shells.contains(c), let p = program(named: c) { return p }
        }
        if let first = terminal.argv.first, let p = program(named: first) { return p }
        return nil
    }

    public func displayName(for terminal: Terminal) -> String {
        if let p = program(for: terminal) { return p.name }
        if let app = terminal.status?.app { return app }
        if let n = terminal.foreground?.name, !n.isEmpty { return n }
        return terminal.name ?? terminal.localAddress
    }
}
