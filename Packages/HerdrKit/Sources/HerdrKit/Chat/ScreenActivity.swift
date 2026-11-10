import Foundation

public struct ScreenActivity: Sendable, Hashable {
    public var label: String
    public var detail: String?

    public init(label: String, detail: String? = nil) {
        self.label = label
        self.detail = detail
    }

    public static func parse(_ screen: String) -> ScreenActivity? {
        let lines = screen.components(separatedBy: "\n").suffix(40)
        for raw in lines.reversed() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("●") || line.hasPrefix("⏺") { return nil }
            if let m = line.wholeMatch(of: /[·✢✳✶✻✽*]\s+([A-Za-z][A-Za-z' -]{0,40}?)…\s*(?:\((.*)\))?.*/) {
                return ScreenActivity(label: String(m.1) + "…", detail: clean(m.2.map(String.init)))
            }
            if let m = line.wholeMatch(of: /[•◦]\s+([A-Za-z][A-Za-z' -]{0,40}?)\s*\((.*esc to interrupt.*)\).*/) {
                return ScreenActivity(label: String(m.1) + "…", detail: clean(String(m.2)))
            }
        }
        return nil
    }

    static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let parts = s.components(separatedBy: CharacterSet(charactersIn: "·•"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().contains("esc to interrupt") && !$0.lowercased().hasPrefix("ctrl+") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
