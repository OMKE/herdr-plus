import SwiftUI

struct MarkdownText: View {
    let text: String

    struct Item: Hashable {
        let indent: Int
        let marker: String
        let text: String
    }

    enum Block: Hashable {
        case paragraph(String)
        case heading(Int, String)
        case code(String, String)
        case table([String])
        case list([Item])
        case rule
    }

    static var body: Color { Theme.body }
    static var codeInk: Color { Theme.codeInk }

    var body: some View {
        let blocks = Self.blocks(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                view(b)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(_ b: Block) -> some View {
        switch b {
        case .paragraph(let s):
            prose(s)
        case .heading(let level, let s):
            Text(Self.inline(s, size: level <= 1 ? 18 : level == 2 ? 16.5 : 15.5))
                .font(Typo.chat(level <= 1 ? 18 : level == 2 ? 16.5 : 15.5, .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        case .list(let items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(it.marker)
                            .font(Typo.chat(it.marker == "•" ? 15 : 14, .medium).monospacedDigit())
                            .foregroundStyle(Theme.dim)
                            .frame(minWidth: 12, alignment: .trailing)
                        prose(it.text)
                    }
                    .padding(.leading, CGFloat(it.indent) * 18)
                }
            }
        case .code(let lang, let body):
            VStack(alignment: .leading, spacing: 0) {
                if !lang.isEmpty {
                    Text(lang).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                        .padding(.horizontal, 12).padding(.top, 8)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(body)
                        .font(Typo.code(12.5))
                        .lineSpacing(3)
                        .foregroundStyle(Self.body)
                        .padding(12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chromeDeep))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        case .table(let lines):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Self.alignTable(lines))
                    .font(Typo.code(12))
                    .lineSpacing(3)
                    .foregroundStyle(Self.body)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chromeDeep))
        case .rule:
            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 2)
        }
    }

    private func prose(_ s: String) -> some View {
        Text(Self.inline(s, size: 15))
            .font(Typo.chat(15))
            .lineSpacing(4.5 * Typo.scale)
            .foregroundStyle(Self.body)
            .tint(Theme.blue)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func inline(_ s: String, size: CGFloat) -> AttributedString {
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        for run in a.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                a[run.range].font = Typo.code(size - 2)
                a[run.range].foregroundColor = codeInk
                a[run.range].backgroundColor = Theme.raised
            } else if intent.contains(.stronglyEmphasized) {
                a[run.range].foregroundColor = Theme.text
            }
        }
        return a
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var items: [Item] = []
        var lines = text.components(separatedBy: "\n")[...]
        func flushPara() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }
        func flushList() {
            if !items.isEmpty { out.append(.list(items)); items = [] }
        }
        func flush() { flushPara(); flushList() }
        while let line = lines.popFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                flush()
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                while let l = lines.popFirst() {
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    body.append(l)
                }
                out.append(.code(lang, body.joined(separator: "\n")))
            } else if t.hasPrefix("|") {
                flush()
                var rows = [t]
                while let l = lines.first, l.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(l.trimmingCharacters(in: .whitespaces))
                    lines = lines.dropFirst()
                }
                out.append(.table(rows))
            } else if let m = t.wholeMatch(of: /(#{1,6})\s+(.*)/) {
                flush()
                out.append(.heading(m.1.count, String(m.2)))
            } else if t == "---" || t == "***" || t == "___" {
                flush()
                out.append(.rule)
            } else if t.isEmpty {
                flushPara()
            } else if let it = listItem(line) {
                flushPara()
                items.append(it)
            } else if !items.isEmpty, line.first == " " || line.first == "\t" {
                let last = items.removeLast()
                items.append(Item(indent: last.indent, marker: last.marker, text: last.text + " " + t))
            } else {
                flushList()
                para.append(line)
            }
        }
        flush()
        return out
    }

    static func listItem(_ line: String) -> Item? {
        if let m = line.wholeMatch(of: /(\s*)[-*+]\s+(.*)/) {
            return Item(indent: min(m.1.count / 2, 4), marker: "•", text: String(m.2))
        }
        if let m = line.wholeMatch(of: /(\s*)(\d{1,3})[.)]\s+(.*)/) {
            return Item(indent: min(m.1.count / 2, 4), marker: "\(m.2).", text: String(m.3))
        }
        return nil
    }

    static func cells(_ row: String) -> [String] {
        var r = Substring(row)
        if r.hasPrefix("|") { r = r.dropFirst() }
        if r.hasSuffix("|") { r = r.dropLast() }
        return r.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func alignTable(_ rows: [String]) -> String {
        let parsed = rows.map(cells).filter { !$0.allSatisfy { $0.allSatisfy { "-: ".contains($0) } && !$0.isEmpty } }
        let n = parsed.map(\.count).max() ?? 0
        var widths = Array(repeating: 0, count: n)
        for r in parsed { for (i, c) in r.enumerated() { widths[i] = max(widths[i], c.count) } }
        return parsed.enumerated().map { k, r in
            let line = (0..<n).map { i in
                let c = i < r.count ? r[i] : ""
                return c + String(repeating: " ", count: widths[i] - c.count)
            }.joined(separator: "  ")
            return k == 0 && parsed.count > 1 ? line + "\n" + widths.map { String(repeating: "─", count: $0) }.joined(separator: "  ") : line
        }.joined(separator: "\n")
    }
}
