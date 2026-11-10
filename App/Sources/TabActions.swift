import Foundation
import HerdrKit

enum AgentCatalog {
    static let keys = ["claude", "codex", "opencode", "gemini", "cursor", "copilot", "amp", "pi", "grok", "kimi", "crush"]

    static func agents(_ programs: Programs) -> [Program] {
        keys.compactMap { programs.programs[$0] }.filter { !$0.run.isEmpty }
    }

    static func canRenameSession(_ p: Program?) -> Bool { p?.key == "claude" }
}

extension AppModel {
    private func local(_ address: String, machine: String?) -> String {
        guard let machine, address.hasPrefix(machine + "/") else { return address }
        return String(address.dropFirst(machine.count + 1))
    }

    func newTab(in space: Space, program: Program?, name: String = "", after: String? = nil) async throws {
        guard let c = connection else { throw CoreError.disconnected }
        let tabID = LayoutEdit.freshID("tb")
        let paneID = LayoutEdit.freshID("p")
        let argv = program.map { LayoutEdit.agentArgv($0.run, remote: space.machine != nil) } ?? []
        let addr = try await c.runTerminal(argv: argv, cwd: space.folder, labels: ["herdr.space": space.id, "herdr.tab": tabID, "herdr.seen": "0"], on: space.machine)
        let tab = LayoutEdit.tab(id: tabID, name: name.trimmingCharacters(in: .whitespaces), pane: paneID, terminal: local(addr, machine: space.machine))
        do {
            try await c.editLayout(on: space.machine) { try LayoutEdit.adding(tab, to: $0, space: space.id, after: after) }
        } catch {
            try? await c.killTerminal(addr)
            throw error
        }
        await refreshLayouts()
        select(TabRef(spaceUID: space.uid, tabID: tabID), pane: paneID)
    }

    func renameTab(_ ref: TabRef, to name: String, renameSession: Bool) async throws {
        guard let c = connection, let (space, tab) = tab(ref) else { throw CoreError.disconnected }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await c.editLayout(on: space.machine) { try LayoutEdit.renaming(tab: tab.id, to: clean, in: $0, space: space.id) }
        if renameSession, !clean.isEmpty, let t = primaryTerminal(tab, in: space), AgentCatalog.canRenameSession(programs.program(for: t)) {
            try? await c.sendText(terminal: t.address, text: "/rename " + clean)
        }
        await refreshLayouts()
    }

    func closeTab(_ ref: TabRef) async throws {
        guard let c = connection, let (space, tab) = tab(ref) else { throw CoreError.disconnected }
        let addrs = tab.terminals.map { LayoutDocument.address($0, machine: space.machine) }
        try await c.editLayout(on: space.machine) { try LayoutEdit.removing(tab: tab.id, from: $0, space: space.id) }
        for a in addrs { try? await c.killTerminal(a) }
        if selectedTab == ref { selectedTab = nil }
        await refreshLayouts()
    }
}
