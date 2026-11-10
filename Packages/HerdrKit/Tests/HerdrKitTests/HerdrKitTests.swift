import Foundation
import Testing
@testable import HerdrKit

@Test func frameRoundTrip() throws {
    let f = Frame(channel: 7, kind: .data, payload: Data("hello".utf8))
    var dec = FrameDecoder()
    let bytes = f.encoded() + Frame.credit(channel: 7, bytes: 1024).encoded()
    var out: [Frame] = []
    for b in bytes { out += try dec.push(Data([b])) }
    #expect(out.count == 2)
    #expect(out[0] == f)
    #expect(out[1].frameKind == .credit)
    #expect(out[1].payload.readLE(UInt32.self, at: out[1].payload.startIndex) == 1024)
}

@Test func frameTooLarge() {
    var dec = FrameDecoder()
    var header = Data()
    header.appendLE(UInt32(1))
    header.append(0)
    header.appendLE(UInt32(FrameDecoder.maxPayload + 1))
    #expect(throws: FrameError.self) { try dec.push(header) }
}

@Test func lineDecoderKeepsRemainder() {
    var d = LineDecoder()
    let lines = d.push(Data("{\"a\":1}\n{\"b\"".utf8))
    #expect(lines.count == 1)
    #expect(d.takeRemainder() == Data("{\"b\"".utf8))
}

@Test func storeAppliesEvents() {
    var s = TerminalStore()
    s.reset(seq: 5, terminals: [Terminal(address: "t1", title: "a")])
    let applied = s.apply(TerminalEvent(seq: 5, type: "title", terminal: "t1", data: ["title": "old"]))
    #expect(!applied)
    s.apply(TerminalEvent(seq: 6, type: "status", terminal: "t1", data: ["status": ["state": "blocked", "app": "claude-code", "msg": "Proceed?"], "reported": true]))
    #expect(s["t1"]?.agentState == .blocked)
    #expect(s["t1"]?.status?.msg == "Proceed?")
    s.apply(TerminalEvent(seq: 7, type: "created", terminal: "ubuntu/t2", data: ["address": "ubuntu/t2", "argv": ["zsh"], "cwd": "/home/x/proj"]))
    #expect(s.all.count == 2)
    #expect(s["ubuntu/t2"]?.machine == "ubuntu")
    #expect(s["ubuntu/t2"]?.localAddress == "t2")
    s.apply(TerminalEvent(seq: 8, type: "finished", terminal: "t1", data: ["reason": "exited", "exit_code": 0]))
    #expect(s["t1"]?.isLive == false)
    s.apply(TerminalEvent(seq: 9, type: "removed", terminal: "t1", data: [:]))
    #expect(s.all.map(\.address) == ["ubuntu/t2"])
}

let sampleDoc: JSONValue = [
    "spaces": [
        ["id": "s1", "name": "", "folder": "/Users/x/website", "tabs": [
            ["id": "tb1", "name": "main", "root": ["id": "r", "type": "row", "children": [
                ["id": "p1", "type": "block", "content": ["terminal": "t3"]],
                ["id": "p2", "type": "column", "children": [
                    ["id": "p3", "type": "block", "content": ["mod": "git", "props": [:]]],
                    ["id": "p4", "type": "block", "content": ["terminal": "t4"]],
                ]],
            ]]],
        ]],
    ],
]

@Test func layoutParses() {
    let doc = LayoutDocument(value: sampleDoc, version: 3)
    #expect(doc.spaces.count == 1)
    let s = doc.spaces[0]
    #expect(s.displayName == "website")
    #expect(s.monogram == "WE")
    #expect(s.tabs[0].panes.count == 3)
    #expect(s.tabs[0].terminals == ["t3", "t4"])
    if case .mod(let name, _) = s.tabs[0].panes[1].content { #expect(name == "git") } else { Issue.record("expected mod") }
}

@Test func remoteAddresses() {
    let doc = LayoutDocument(value: sampleDoc, version: 1, machine: "ubuntu")
    let a = Terminal(address: "ubuntu/t3", status: Status(state: "blocked", app: "claude-code"))
    let b = Terminal(address: "ubuntu/t4", status: Status(state: "working", app: "codex"))
    let entries = AgentOrdering.entries(spaces: doc.spaces, terminals: [b, a])
    #expect(entries.map(\.id) == ["ubuntu/t3", "ubuntu/t4"])
    #expect(AgentOrdering.needsYou(entries).map(\.id) == ["ubuntu/t3"])
}

@Test func programsMatch() {
    let p = Programs.bundled
    #expect(p.programs["claude"] != nil)
    let t = Terminal(address: "t1", status: Status(state: "idle", app: "claude-code"))
    #expect(p.displayName(for: t) == "Claude Code")
    var shell = Terminal(address: "t2", argv: ["zsh"])
    shell.foreground = Foreground(pid: 1, name: "node", argv: ["node", "/usr/local/bin/codex"], cwd: nil)
    #expect(p.program(for: shell)?.key == "codex")
}

@Test func notificationText() {
    let doc = LayoutDocument(value: sampleDoc, version: 1)
    let t = Terminal(address: "t3", cwd: "/Users/x/website", status: Status(state: "blocked", app: "claude-code", msg: String(repeating: "Do you want to proceed with the migration? ", count: 6)))
    let n = NotificationText.make(terminal: t, spaces: doc.spaces, programs: .bundled, screen: nil)
    #expect(n.title == "Claude Code · website")
    #expect(n.body.hasSuffix("…"))
    #expect(n.body.count <= 140)
    #expect(n.click == "herdr-ios://terminal/t3")
    #expect(NotificationText.clickURL(for: "ubuntu/t7") == "herdr-ios://terminal/ubuntu%2Ft7")
}

func isolatedEnv() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["HC_SESSION"] = "hp"
    env["XDG_STATE_HOME"] = "/tmp/hcios/state"
    env["XDG_CONFIG_HOME"] = "/tmp/hcios/config"
    try? FileManager.default.createDirectory(atPath: "/tmp/hcios/state", withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(atPath: "/tmp/hcios/config", withIntermediateDirectories: true)
    return env
}

let hc = FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/hc"

@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: hc)), .timeLimit(.minutes(1)))
func integrationAgainstIsolatedCore() async throws {
    let transport = try ProcessTransport(executable: hc, arguments: ["connect"], environment: isolatedEnv())
    let c = CoreConnection(transport: transport)
    let info = try await c.start()
    #expect(info.features.contains("automatic_input"))
    let sub = try await c.subscribeEvents()
    let run = try await c.call("terminal.run", ["argv": ["/bin/sh", "-c", "printf 'ready\\n'; read line; printf 'got:%s\\n' \"$line\"; printf '\\033]7501;state=blocked:app=probe\\033\\\\'; sleep 30"], "name": "ios-it"])
    let addr = try #require(run["address"]?.string)
    var store = TerminalStore()
    store.reset(seq: sub.seq, terminals: sub.terminals)
    let att = try await c.attach(terminal: addr, cols: 60, rows: 12, history: 50)
    var output = Data()
    var sentInput = false
    var it = att.stream.makeAsyncIterator()
    while let m = await it.next() {
        if case .data(let d) = m {
            output.append(d)
            await c.credit(channel: att.channel, bytes: d.count)
            let text = String(decoding: output, as: UTF8.self)
            if text.contains("ready"), !sentInput {
                sentInput = true
                await c.input(channel: att.channel, Data("hi phone\r".utf8))
            }
            if text.contains("got:hi phone") { break }
        }
    }
    #expect(String(decoding: output, as: UTF8.self).contains("got:hi phone"))
    var events = sub.stream.makeAsyncIterator()
    var sawBlocked = false
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, let n = await events.next() {
        if case .event(let e) = n {
            store.apply(e)
            if store[addr]?.agentState == .blocked { sawBlocked = true; break }
        }
    }
    #expect(sawBlocked)
    let text = try await c.read(terminal: addr, lines: 10)
    #expect(text.contains("got:hi phone"))
    _ = try await c.call("terminal.kill", ["terminal": .string(addr)])
    await c.close()
}
