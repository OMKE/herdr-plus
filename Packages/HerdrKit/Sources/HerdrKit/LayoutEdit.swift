import Foundation

public enum LayoutEditError: Error, CustomStringConvertible {
    case missing(String)
    case conflict

    public var description: String {
        switch self {
        case .missing(let s): "Not found: \(s)"
        case .conflict: "The layout changed on another screen. Try again."
        }
    }
}

public enum LayoutEdit {
    public static func freshID(_ prefix: String) -> String {
        let hex = (0..<32).map { _ in String(UInt8.random(in: 0...15), radix: 16) }.joined()
        return prefix + hex
    }

    public static func tab(id: String, name: String, pane: String, terminal: String) -> JSONValue {
        [
            "id": .string(id),
            "name": .string(name),
            "root": [
                "id": .string(id),
                "type": "row",
                "children": [["id": .string(pane), "type": "block", "content": ["terminal": .string(terminal)]]],
            ],
        ]
    }

    static func mapTabs(_ doc: JSONValue, space: String, _ f: ([JSONValue]) throws -> [JSONValue]) throws -> JSONValue {
        guard case .object(var root) = doc, let spaces = root["spaces"]?.array else { throw LayoutEditError.missing("layout") }
        guard let si = spaces.firstIndex(where: { $0["id"]?.string == space }), case .object(var s) = spaces[si] else { throw LayoutEditError.missing("space") }
        s["tabs"] = .array(try f(s["tabs"]?.array ?? []))
        var out = spaces
        out[si] = .object(s)
        root["spaces"] = .array(out)
        return .object(root)
    }

    public static func adding(_ tab: JSONValue, to doc: JSONValue, space: String, after: String? = nil) throws -> JSONValue {
        try mapTabs(doc, space: space) { tabs in
            var t = tabs
            if let after, let i = t.firstIndex(where: { $0["id"]?.string == after }) {
                t.insert(tab, at: i + 1)
            } else {
                t.append(tab)
            }
            return t
        }
    }

    public static func renaming(tab: String, to name: String, in doc: JSONValue, space: String) throws -> JSONValue {
        try mapTabs(doc, space: space) { tabs in
            guard let i = tabs.firstIndex(where: { $0["id"]?.string == tab }), case .object(var o) = tabs[i] else { throw LayoutEditError.missing("tab") }
            o["name"] = .string(name)
            var t = tabs
            t[i] = .object(o)
            return t
        }
    }

    public static func removing(tab: String, from doc: JSONValue, space: String) throws -> JSONValue {
        try mapTabs(doc, space: space) { tabs in
            guard tabs.contains(where: { $0["id"]?.string == tab }) else { throw LayoutEditError.missing("tab") }
            return tabs.filter { $0["id"]?.string != tab }
        }
    }

    public static func agentArgv(_ command: [String], remote: Bool) -> [String] {
        if remote {
            let script = "shell=${SHELL:-/bin/sh}\ncase \"${shell##*/}\" in\n  fish) exec \"$shell\" -lic 'command $argv[2..]; exec $argv[1] -li' \"$shell\" \"$@\" ;;\n  sh|bash|zsh|dash|ksh) exec \"$shell\" -lic '\"$@\"; exec \"$0\" -li' \"$shell\" \"$@\" ;;\n  *) exec sh -c '\"$@\"; exec \"${SHELL:-sh}\" -i' sh \"$@\" ;;\nesac"
            return ["sh", "-c", script, "sh"] + command
        }
        let script = "shell=${SHELL:-/bin/zsh}\ncase \"${shell##*/}\" in\n  fish) exec \"$shell\" -lic 'command $argv[2..]; exec $argv[1] -li' \"$shell\" \"$@\" ;;\n  *) exec \"$shell\" -lic '\"$@\"; exec \"$0\" -li' \"$shell\" \"$@\" ;;\nesac"
        return ["/bin/sh", "-c", script, "sh"] + command
    }
}

extension CoreConnection {
    public func rawLayout(on machine: String? = nil) async throws -> (value: JSONValue, version: Int) {
        var p: [String: JSONValue] = ["name": "herdr-app"]
        if let machine { p["on"] = .string(machine) }
        let r = try await call("doc.get", .object(p))
        let v = r["value"] ?? .null
        return (v.isNull ? ["spaces": []] : v, r["version"]?.int ?? 0)
    }

    public func setLayout(_ value: JSONValue, version: Int, on machine: String? = nil) async throws {
        var p: [String: JSONValue] = ["name": "herdr-app", "value": value, "version": .number(Double(version))]
        if let machine { p["on"] = .string(machine) }
        do {
            _ = try await call("doc.set", .object(p))
        } catch let e as RPCError where e.message.lowercased().contains("conflict") || e.data?["kind"]?.string == "conflict" {
            throw LayoutEditError.conflict
        }
    }

    public func editLayout(on machine: String? = nil, _ f: (JSONValue) throws -> JSONValue) async throws {
        var lastError: Error = LayoutEditError.conflict
        for _ in 0..<3 {
            let (v, ver) = try await rawLayout(on: machine)
            let next = try f(v)
            do {
                try await setLayout(next, version: ver, on: machine)
                return
            } catch LayoutEditError.conflict {
                lastError = LayoutEditError.conflict
                continue
            }
        }
        throw lastError
    }

    public func runTerminal(argv: [String], cwd: String?, labels: [String: String], on machine: String? = nil) async throws -> String {
        var p: [String: JSONValue] = [
            "argv": .array(argv.map { .string($0) }),
            "env": ["TERM": "xterm-256color", "COLORTERM": "truecolor", "TERM_PROGRAM": "herdr"],
            "labels": .object(labels.mapValues { .string($0) }),
            "keep": true,
        ]
        if let cwd, !cwd.isEmpty { p["cwd"] = .string(cwd) }
        if let machine { p["on"] = .string(machine) }
        let r = try await call("terminal.run", .object(p))
        guard let a = r["address"]?.string else { throw CoreError.badResponse("terminal.run") }
        return a
    }

    public func killTerminal(_ address: String) async throws {
        _ = try await call("terminal.kill", ["terminal": .string(address)])
    }
}
