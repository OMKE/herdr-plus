import Foundation
import Testing
@testable import HerdrKit

@Test func todoRoundTrip() {
    let items = [TodoItem(text: "a", spaceUID: "/sp", tabID: "tb", label: "web / main", program: "claude"), TodoItem(text: "b", done: true)]
    let back = TodoDoc.decode(TodoDoc.encode(items))
    #expect(back.map(\.text) == ["a", "b"])
    #expect(back[0].tabID == "tb" && back[1].done)
    #expect(abs(back[0].created.timeIntervalSince(items[0].created)) < 1)
}

@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: hc)), .timeLimit(.minutes(1)))
func todosAgainstIsolatedCore() async throws {
    let transport = try ProcessTransport(executable: hc, arguments: ["connect"], environment: isolatedEnv())
    let c = CoreConnection(transport: transport)
    _ = try await c.start()
    defer { Task { await c.close() } }
    _ = try await c.editTodos { _ in [] }
    _ = try await c.editTodos { $0 + [TodoItem(text: "one")] }
    let after = try await c.editTodos { $0.map { var t = $0; t.done = true; return t } }
    #expect(after.count == 1 && after[0].done)
    let (items, _) = try await c.todos()
    #expect(items.first?.text == "one" && items.first?.done == true)
}
