import Foundation
import Testing
@testable import HerdrKit

@Test func realLogParses() throws {
    guard let path = ProcessInfo.processInfo.environment["HK_REAL_LOG"] else { return }
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let start = Date()
    let p = ConversationParser.parse(lines: text.split(separator: "\n").map(String.init))
    let items = p.items()
    let rows = ChatRows.build(items)
    var counts: [String: Int] = [:]
    for r in rows {
        let k: String
        switch r.kind {
        case .user: k = "user"
        case .assistant: k = "assistant"
        case .tools: k = "tools"
        case .permission: k = "permission"
        case .question: k = "question"
        case .status: k = "status"
        case .separator: k = "separator"
        case .footer: k = "footer"
        }
        counts[k, default: 0] += 1
    }
    print("REAL", path.split(separator: "/").last ?? "", "items", items.count, "rows", rows.count, counts.sorted { $0.key < $1.key }, "ms", Int(Date().timeIntervalSince(start) * 1000), "model", p.model ?? "-")
}

@Test func lstartMatchesShiftedProcStart() {
    let a = Locator.parseStart("Mon Nov  9 19:44:45 2026")!
    let b = Locator.parseStart("Mon Nov  9 20:44:45 2026")!
    #expect(Locator.sameStart(a, b))
    #expect(!Locator.sameStart(a, b.addingTimeInterval(30)))
}
