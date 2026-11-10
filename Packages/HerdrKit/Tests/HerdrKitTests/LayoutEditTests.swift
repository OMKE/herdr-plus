import Foundation
import Testing
@testable import HerdrKit

private let sample: JSONValue = [
    "spaces": [[
        "id": "sp1", "name": "", "folder": "/x", "extra": "keep",
        "tabs": [
            ["id": "tb1", "name": "main", "root": ["id": "tb1", "type": "row", "children": []], "future": 1],
            ["id": "tb2", "name": "two", "root": ["id": "tb2", "type": "row", "children": []]],
        ],
    ]],
]

@Test func layoutEditAddsAfterAndKeepsUnknownFields() throws {
    let t = LayoutEdit.tab(id: "tbN", name: "new", pane: "pN", terminal: "t9")
    let out = try LayoutEdit.adding(t, to: sample, space: "sp1", after: "tb1")
    let tabs = try #require(out["spaces"]?.array?.first?["tabs"]?.array)
    #expect(tabs.map { $0["id"]?.string } == ["tb1", "tbN", "tb2"])
    #expect(out["spaces"]?.array?.first?["extra"]?.string == "keep")
    #expect(tabs[0]["future"]?.int == 1)
    let doc = LayoutDocument(value: out, version: 1)
    #expect(doc.spaces[0].tabs[1].terminals == ["t9"])
}

@Test func layoutEditRenameAndRemove() throws {
    let r = try LayoutEdit.renaming(tab: "tb2", to: "renamed", in: sample, space: "sp1")
    #expect(LayoutDocument(value: r, version: 1).spaces[0].tabs[1].name == "renamed")
    let d = try LayoutEdit.removing(tab: "tb1", from: r, space: "sp1")
    #expect(LayoutDocument(value: d, version: 1).spaces[0].tabs.map(\.id) == ["tb2"])
    #expect(throws: LayoutEditError.self) { try LayoutEdit.removing(tab: "nope", from: d, space: "sp1") }
}

@Test func freshIDShape() {
    let id = LayoutEdit.freshID("tb")
    #expect(id.hasPrefix("tb") && id.count == 34)
}

@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: hc)), .timeLimit(.minutes(1)))
func layoutEditAgainstIsolatedCore() async throws {
    let transport = try ProcessTransport(executable: hc, arguments: ["connect"], environment: isolatedEnv())
    let c = CoreConnection(transport: transport)
    _ = try await c.start()
    defer { Task { await c.close() } }
    let (_, v0) = try await c.rawLayout()
    try await c.setLayout(["spaces": [["id": "spT", "name": "test", "folder": "/tmp", "tabs": []]]], version: v0)
    let addr = try await c.runTerminal(argv: LayoutEdit.agentArgv(["/bin/echo", "hi"], remote: false), cwd: "/tmp", labels: ["herdr.space": "spT", "herdr.tab": "tbT"])
    try await c.editLayout { try LayoutEdit.adding(LayoutEdit.tab(id: "tbT", name: "", pane: "pT", terminal: addr), to: $0, space: "spT") }
    try await c.editLayout { try LayoutEdit.renaming(tab: "tbT", to: "renamed", in: $0, space: "spT") }
    var doc = try await c.layout()
    #expect(doc.spaces.first?.tabs.first?.name == "renamed")
    #expect(doc.spaces.first?.tabs.first?.terminals == [addr])
    let (_, stale) = try await c.rawLayout()
    try await c.setLayout(["spaces": []], version: stale)
    await #expect(throws: LayoutEditError.self) { try await c.setLayout(["spaces": []], version: stale) }
    try? await c.killTerminal(addr)
    doc = try await c.layout()
    #expect(doc.spaces.isEmpty)
}
