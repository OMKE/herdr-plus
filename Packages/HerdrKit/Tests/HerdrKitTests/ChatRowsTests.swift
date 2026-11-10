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
