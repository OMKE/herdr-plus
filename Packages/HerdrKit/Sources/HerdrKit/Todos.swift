import Foundation

public struct TodoItem: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var text: String
    public var done: Bool
    public var created: Date
    public var spaceUID: String?
    public var tabID: String?
    public var label: String?
    public var program: String?

    public init(id: String = UUID().uuidString, text: String, done: Bool = false, created: Date = Date(), spaceUID: String? = nil, tabID: String? = nil, label: String? = nil, program: String? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.created = created
        self.spaceUID = spaceUID
        self.tabID = tabID
        self.label = label
        self.program = program
    }
}

public enum TodoDoc {
    public static let name = "herdr-ios-todos"

    public static func decode(_ v: JSONValue) -> [TodoItem] {
        guard let items = v["items"], let data = try? JSONEncoder().encode(items) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return (try? d.decode([TodoItem].self, from: data)) ?? []
    }

    public static func encode(_ items: [TodoItem]) -> JSONValue {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        guard let data = try? e.encode(items), let v = try? JSONDecoder().decode(JSONValue.self, from: data) else { return ["items": []] }
        return ["items": v]
    }
}

extension CoreConnection {
    public func todos() async throws -> (items: [TodoItem], version: Int) {
        let r = try await call("doc.get", ["name": .string(TodoDoc.name)])
        return (TodoDoc.decode(r["value"] ?? .null), r["version"]?.int ?? 0)
    }

    public func editTodos(_ f: ([TodoItem]) -> [TodoItem]) async throws -> [TodoItem] {
        for _ in 0..<3 {
            let (items, ver) = try await todos()
            let next = f(items)
            do {
                _ = try await call("doc.set", ["name": .string(TodoDoc.name), "version": .number(Double(ver)), "value": TodoDoc.encode(next)])
                return next
            } catch let e as RPCError where e.message.lowercased().contains("conflict") || e.data?["kind"]?.string == "conflict" {
                continue
            }
        }
        throw LayoutEditError.conflict
    }
}
