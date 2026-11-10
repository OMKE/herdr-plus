import Foundation
import Testing
@testable import HerdrKit

@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: hc)), .timeLimit(.minutes(1)))
func chatPrimitivesAgainstIsolatedCore() async throws {
    let transport = try ProcessTransport(executable: hc, arguments: ["connect"], environment: isolatedEnv())
    let c = CoreConnection(transport: transport)
    _ = try await c.start()
    let screenFile = FileManager.default.temporaryDirectory.appendingPathComponent("hk-approval-\(UUID().uuidString).txt")
    try Data(approvalScreen.utf8).write(to: screenFile)
    let run = try await c.call("terminal.run", ["argv": ["/bin/sh", "-c", "cat \"$0\"; IFS= read -r k; printf 'key:%s\\n' \"$k\"; sleep 30", .string(screenFile.path)], "name": "ios-chat-it", "cols": 80, "rows": 24])
    let addr = try #require(run["address"]?.string)
    defer { Task { _ = try? await c.call("terminal.kill", ["terminal": .string(addr)]); await c.close() } }

    let list = try await c.terminals()
    let t = try #require(list.first { $0.address == addr })
    #expect(t.pid != nil)

    var screen = ""
    for _ in 0..<30 {
        screen = try await c.screen(terminal: addr)
        if screen.contains("Do you want") { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    let card = ScreenCards.approval(screen)
    #expect(card?.command == "swift build --product x")

    try await c.keys(terminal: addr, ["1", "enter"])
    var got = false
    for _ in 0..<30 {
        if try await c.screen(terminal: addr).contains("key:1") { got = true; break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(got)

    let r = try await c.shell("printf '%s|%s' \"$1\" \"$2\"", ["a b", "c"])
    #expect(r.text == "a b|c")
    let ps = try await c.exec(["ps", "-A", "-ww", "-o", "pid=,ppid=,lstart=,command="])
    let procs = Locator.parsePS(ps.text)
    #expect(procs.count > 5)
    #expect(procs.values.contains { $0.start != nil })

    let home = FileManager.default.temporaryDirectory.appendingPathComponent("hk-claude-\(UUID().uuidString)")
    let sid = "11111111-2222-3333-4444-555555555555"
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("projects/p"), withIntermediateDirectories: true)
    let log = home.appendingPathComponent("projects/p/\(sid).jsonl")
    try Data("{\"type\":\"user\",\"uuid\":\"u\",\"message\":{\"role\":\"user\",\"content\":\"hello from log\"}}\n".utf8).write(to: log)
    let fake = home.appendingPathComponent("claude")
    let src = home.appendingPathComponent("claude.c")
    try Data("""
    #include <stdio.h>
    #include <stdlib.h>
    #include <unistd.h>
    int main(void) {
      char cmd[2048];
      snprintf(cmd, sizeof cmd, "printf '{\\"pid\\":%d,\\"sessionId\\":\\"\(sid)\\",\\"procStart\\":\\"%%s\\"}' \\"$(ps -o lstart= -p %d | sed 's/^ *//')\\" > \\"$CLAUDE_CONFIG_DIR/sessions/%d.json\\"", getpid(), getpid(), getpid());
      system(cmd);
      sleep(30);
      return 0;
    }
    """.utf8).write(to: src)
    let cc = Process()
    cc.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
    cc.arguments = ["-o", fake.path, src.path]
    try cc.run()
    cc.waitUntilExit()
    #expect(cc.terminationStatus == 0)
    let run2 = try await c.call("terminal.run", ["argv": ["/usr/bin/env", .string("CLAUDE_CONFIG_DIR=\(home.path)"), .string(fake.path)], "name": "ios-claude-it"])
    let addr2 = try #require(run2["address"]?.string)
    try await Task.sleep(for: .milliseconds(800))
    var t2 = try #require(try await c.terminals().first { $0.address == addr2 })
    t2.status = Status(state: "idle", app: "claude")
    let found = try await Locator.locate(t2, via: c)
    _ = try? await c.call("terminal.kill", ["terminal": .string(addr2)])
    #expect(found?.path.hasSuffix("projects/p/\(sid).jsonl") == true)
    #expect(found?.dir == home.path)
    if let found {
        var tail = LogTail(path: found.path)
        _ = try await tail.poll(via: c, on: nil)
        #expect(tail.parser.items().first?.kind == .user("hello from log"))
    }

    let path = try await c.put(terminal: addr, name: "probe.txt", data: Data("hello".utf8))
    #expect(!path.isEmpty)
    if !path.isEmpty { #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "hello") }
}
