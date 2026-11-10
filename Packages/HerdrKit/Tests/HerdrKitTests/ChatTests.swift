import Foundation
import Testing
@testable import HerdrKit

private func j(_ o: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
}

@Test func claudeConversation() {
    let lines = [
        j(["type": "user", "uuid": "u1", "timestamp": "2026-11-10T10:00:00.000Z", "message": ["role": "user", "content": "fix the build"]]),
        j(["type": "assistant", "uuid": "a1", "timestamp": "2026-11-10T10:00:05.000Z", "message": ["id": "m1", "model": "claude-x", "content": [
            ["type": "thinking", "thinking": "look first"],
            ["type": "tool_use", "id": "t1", "name": "Read", "input": ["file_path": "/a.swift"]],
        ]]]),
        j(["type": "user", "uuid": "r1", "timestamp": "2026-11-10T10:00:06.000Z", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": "ok"]]]]),
        j(["type": "assistant", "uuid": "a2", "timestamp": "2026-11-10T10:00:07.000Z", "message": ["id": "m2", "content": [
            ["type": "tool_use", "id": "t2", "name": "Read", "input": ["file_path": "/b.swift"]],
        ]]]),
        j(["type": "user", "uuid": "r2", "timestamp": "2026-11-10T10:00:08.000Z", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t2", "content": "ok"]]]]),
        j(["type": "assistant", "uuid": "a3", "timestamp": "2026-11-10T10:00:09.000Z", "message": ["id": "m3", "content": [
            ["type": "text", "text": "Done."],
            ["type": "tool_use", "id": "t3", "name": "Bash", "input": ["command": "swift build"]],
        ]]]),
        j(["type": "user", "uuid": "x", "isSidechain": true, "message": ["role": "user", "content": "hidden"]]),
        j(["type": "user", "uuid": "c", "message": ["role": "user", "content": "<command-name>/clear</command-name>"]]),
    ]
    let p = ConversationParser.parse(lines: lines)
    let items = p.items()
    #expect(p.model == "claude-x")
    guard items.count == 5 else { Issue.record("got \(items.map(\.kind))"); return }
    #expect(items[0].kind == .user("fix the build"))
    #expect(items[1].kind == .assistant("look first"))
    if case .tools(let chips) = items[2].kind { #expect(chips.first?.text == "Read 2 files") } else { Issue.record("no tools") }
    #expect(items[3].kind == .assistant("Done."))
    if case .permission(let r) = items[4].kind {
        #expect(r.title == "Wants to run a command")
        #expect(r.command == "swift build")
    } else { Issue.record("no permission") }
    let rows = ChatRows.build(items, now: ConversationParser.parseTime("2026-11-10T12:00:00Z")!)
    #expect(rows.contains { if case .separator = $0.kind { true } else { false } })
    #expect(!rows.contains { if case .footer = $0.kind { true } else { false } })
    let answered = ChatRows.build(Array(items.dropLast()), now: ConversationParser.parseTime("2026-11-10T12:00:00Z")!)
    #expect(answered.contains { if case .footer(let s) = $0.kind { s.contains("Worked 9s") } else { false } })
}

@Test func claudeQuestionFromLog() {
    let lines = [
        j(["type": "assistant", "uuid": "a1", "message": ["id": "m1", "content": [
            ["type": "tool_use", "id": "q1", "name": "AskUserQuestion", "input": ["questions": [
                ["question": "Which color?", "header": "Color", "multiSelect": false, "options": [["label": "Red (Recommended)", "description": "warm"], ["label": "Blue"]]],
            ]]],
        ]]]),
        j(["type": "user", "uuid": "r1", "toolUseResult": ["answers": ["Which color?": "Blue"]], "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "q1", "content": "x"]]]]),
    ]
    let items = ConversationParser.parse(lines: lines).items()
    guard case .question(let q)? = items.first?.kind else { Issue.record("no question"); return }
    #expect(q.questions[0].options[0].recommended)
    #expect(q.questions[0].options[0].label == "Red")
    #expect(q.state == .answered(["Blue"]))
}

@Test func codexConversation() {
    let lines = [
        j(["type": "turn_context", "payload": ["model": "gpt-x"]]),
        j(["type": "response_item", "timestamp": "2026-11-10T10:00:00Z", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "hello"]]]]),
        j(["type": "response_item", "payload": ["type": "function_call", "name": "exec_command", "call_id": "c1", "arguments": "{\"cmd\":\"ls\"}"]]),
        j(["type": "response_item", "payload": ["type": "function_call_output", "call_id": "c1", "output": "a\nb"]]),
        j(["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Two files."]]]]),
    ]
    let p = ConversationParser.parse(lines: lines)
    let items = p.items()
    #expect(p.model == "gpt-x")
    #expect(items.count == 3)
    #expect(items[0].kind == .user("hello"))
    if case .tools(let c) = items[1].kind { #expect(c[0].calls[0].output == "a\nb") } else { Issue.record("no tools") }
}

@Test func userVisibleFilters() {
    #expect(ConversationParser.userVisible("<local-command-stdout>x</local-command-stdout>") == nil)
    #expect(ConversationParser.userVisible("Caveat: blah") == nil)
    #expect(ConversationParser.userVisible("<pasted_content id=\"a\">body</pasted_content id=\"a\"> after") == "body\n\nafter")
    #expect(ConversationParser.hcNote("<hc from=\"phone\">hi</hc>")?.from == "phone")
}

let approvalScreen = """
 ────────────────────────────────────────────
  Bash command

    swift build --product x

  Do you want to proceed?
  ❯ 1. Yes
    2. Yes, and don't ask again for swift build commands
    3. No, and tell Claude what to do differently (esc)

 Esc to cancel
"""

let questionScreen = """
 ←  ☐ Color  ✔ Submit  →

 Which color should the button be?

 ❯ 1. Red (Recommended)
      warm and loud
   2. Blue
   3. Type something.
 ────────────────────────────────
   4. Chat about this

 Enter to select · ↑/↓ to navigate · Esc to cancel
"""

@Test func approvalCardFromScreen() {
    #expect(ScreenCards.showsPrompt(approvalScreen))
    let c = ScreenCards.approval(approvalScreen)
    #expect(c?.tool == "Bash")
    #expect(c?.command == "swift build --product x")
    #expect(c?.id == ScreenCards.approval(approvalScreen + "\n")?.id)
    #expect(!ScreenCards.showsPrompt(questionScreen))
}

@Test func questionFromScreen() throws {
    let q = try #require(Questions.screenRequest(questionScreen))
    #expect(q.headers == ["Color"])
    #expect(q.questions[0].text == "Which color should the button be?")
    #expect(q.questions[0].options.map(\.label) == ["Red", "Blue"])
    #expect(q.questions[0].options[0].detail == "warm and loud")
    #expect(try Questions.steps(for: q, answers: [QuestionAnswer(picks: [1])]) == [.text("2")])
    #expect(try Questions.steps(for: q, answers: [QuestionAnswer(picks: [], other: "green")]) == [.text("3"), .text("green"), .keys(["enter"])])
    #expect(ScreenCards.approval(questionScreen) == nil)
}

@Test func logTailScriptReadsLines() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hk-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = dir.appendingPathComponent("a.jsonl")
    try Data("{\"a\":1}\n{\"b\":2}\npartial".utf8).write(to: f)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", LogTail.script, "sh", f.path, "-1", "100", "1000"]
    let pipe = Pipe()
    p.standardOutput = pipe
    try p.run()
    p.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(out.hasPrefix("23 0\n"))
    #expect(out.hasSuffix("partial"))
}
