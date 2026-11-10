import Foundation
import Testing
@testable import HerdrKit

private func t(_ s: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + Double(s)) }

private func tool(_ id: String, done: Bool) -> ToolChip {
    ToolChip(id: id, symbol: "terminal", text: "Bash", calls: [ToolCall(id: id, toolName: "Bash", summary: "ls", input: "ls", output: done ? "ok" : nil)])
}

@Test func runningToolKeepsTurnOpen() {
    let items = [
        ChatItem(id: "u", kind: .user("go"), timestamp: t(0)),
        ChatItem(id: "a", kind: .assistant("checking"), timestamp: t(5)),
        ChatItem(id: "b", kind: .tools([tool("x", done: false)]), timestamp: t(9)),
    ]
    let rows = ChatRows.build(items, now: t(20))
    #expect(!rows.contains { if case .footer = $0.kind { true } else { false } })
    #expect(ChatRows.toolRunning(rows))
}

@Test func waitingForApprovalKeepsTurnOpen() {
    let perm = PermissionRequest(title: "Wants to run a command", command: "npm test", toolName: "Bash", toolUseId: "x")
    let items = [
        ChatItem(id: "u", kind: .user("go"), timestamp: t(0)),
        ChatItem(id: "a", kind: .assistant("running tests"), timestamp: t(5)),
        ChatItem(id: "b", kind: .tools([tool("x", done: false)]), timestamp: t(9)),
        ChatItem(id: "p", kind: .permission(perm), timestamp: t(9)),
    ]
    let rows = ChatRows.build(items, now: t(20))
    #expect(!rows.contains { if case .footer = $0.kind { true } else { false } })
}

@Test func pendingQuestionKeepsTurnOpen() {
    let q = QuestionRequest(toolUseId: "q", agent: "claude", questions: [.init(header: "Pick", text: "Which?", options: [.init(label: "A")], multiSelect: false)])
    let items = [
        ChatItem(id: "u", kind: .user("go"), timestamp: t(0)),
        ChatItem(id: "a", kind: .assistant("one question"), timestamp: t(5)),
        ChatItem(id: "q", kind: .question(q), timestamp: t(6)),
    ]
    #expect(!ChatRows.build(items, now: t(20)).contains { if case .footer = $0.kind { true } else { false } })
    var answered = q
    answered.state = .answered(["A"])
    let done = items.dropLast() + [ChatItem(id: "q", kind: .question(answered), timestamp: t(6))]
    #expect(ChatRows.build(Array(done), now: t(20)).contains { if case .footer = $0.kind { true } else { false } })
}

@Test func finishedTurnGetsFooter() {
    let items = [
        ChatItem(id: "u", kind: .user("go"), timestamp: t(0)),
        ChatItem(id: "b", kind: .tools([tool("x", done: true)]), timestamp: t(4)),
        ChatItem(id: "a", kind: .assistant("done"), timestamp: t(9)),
    ]
    let rows = ChatRows.build(items, now: t(20))
    #expect(rows.contains { if case .footer = $0.kind { true } else { false } })
    #expect(!ChatRows.toolRunning(rows))
}
