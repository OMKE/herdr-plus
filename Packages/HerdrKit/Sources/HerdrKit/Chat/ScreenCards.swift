import Foundation

public enum ScreenCards {
    public static let promptMarker = "Do you want"
    public static let clippedTitle = "Command too long to show here. Read it in the terminal before you answer."

    public static func showsPrompt(_ screen: String) -> Bool {
        if screen.contains("Chat about this") || screen.contains("Type something") { return false }
        let lines = screen.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "│|┃ \t")) }
        let yes = /^(?:❯\s*)?1\.\s+Yes\b.*/
        for (i, l) in lines.enumerated() where l.hasPrefix(promptMarker) {
            guard let end = (i..<min(i + 3, lines.count)).first(where: { lines[$0].hasSuffix("?") }) else { continue }
            let next = lines[(end + 1)...].filter { !$0.isEmpty }.prefix(3)
            if next.contains(where: { $0.wholeMatch(of: yes) != nil }) { return true }
        }
        return false
    }

    struct Box {
        var header: String
        var tool: String
        var command: String
        var lines: [String]
        var clipped = false
    }

    static func isCountdown(_ line: String) -> Bool {
        line.hasPrefix("⚠") && line.firstMatch(of: /\b\d{1,2}:\d{2}\b/) != nil
    }

    static func box(_ screen: String) -> Box? {
        let raw = screen.components(separatedBy: "\n")
        guard let ask = raw.lastIndex(where: { $0.contains(promptMarker) }), Questions.claudeParse(screen) == nil else { return nil }
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespaces) }
        let rule = raw[..<ask].lastIndex { trim($0).hasPrefix("─") }
        let top = rule.map { $0 + 1 } ?? 0
        var end = ask
        while end + 1 < raw.count, !trim(raw[end + 1]).isEmpty, !trim(raw[end + 1]).hasPrefix("Esc to cancel") { end += 1 }
        let lines = raw[top...end].map { l -> String in
            let t = trim(l)
            return t.hasPrefix("❯") ? trim(String(t.dropFirst())) : t
        }.filter { !$0.isEmpty && !$0.hasPrefix("Tip:") && !isCountdown($0) }
        guard let header = lines.first, header != lines.last else { return nil }
        let isRule: (String) -> Bool = { $0.hasPrefix("╌") }
        let askAt = lines.lastIndex { $0.contains(promptMarker) } ?? lines.count
        let body = Array(lines[1..<askAt])
        let command: [String]
        if let r1 = body.firstIndex(where: isRule), let r2 = body[(r1 + 1)...].firstIndex(where: isRule) {
            command = Array(body[(r1 + 1)..<r2])
        } else {
            command = body.filter { !isRule($0) }
        }
        let ungutter: (String) -> String = { $0.hasPrefix("│") ? $0.dropFirst().trimmingCharacters(in: .whitespaces) : $0 }
        if rule == nil, header.hasPrefix("│") || body.filter(isRule).count == 1 {
            return Box(header: "", tool: "", command: "", lines: lines, clipped: true)
        }
        let tool = String(header.split(separator: " ").first ?? "")
        return Box(header: header, tool: tool, command: command.map(ungutter).joined(separator: "\n"), lines: lines)
    }

    static func fnv(_ text: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "screen-" + String(h, radix: 16)
    }

    public static func approval(_ screen: String) -> ApprovalCard? {
        guard showsPrompt(screen), let b = box(screen) else { return nil }
        let id = fnv("tool:\(b.tool)\n" + b.lines.joined(separator: "\n"))
        return ApprovalCard(id: id, title: b.clipped ? clippedTitle : b.header, tool: b.tool, command: b.command, clipped: b.clipped)
    }
}

public enum Questions {
    public enum Step: Sendable, Hashable {
        case text(String)
        case keys([String])
        case waitFor(String)
    }

    public enum Failure: Error, Sendable, CustomStringConvertible {
        case notOnScreen
        case unsupported(String)
        case stuck(String)
        public var description: String {
            switch self {
            case .notOnScreen: "The question is no longer on screen."
            case .unsupported(let m): "Cannot answer here: \(m)"
            case .stuck(let m): "Stopped waiting for: \(m)"
            }
        }
    }

    static let recommendedSuffixes = ["(Recommended)", "（Recommended）"]
    public static let codexOtherLabel = "None of the above"

    static func stripRecommended(_ raw: String) -> (String, Bool) {
        let label = raw.trimmingCharacters(in: .whitespaces)
        for suf in recommendedSuffixes where label.hasSuffix(suf) {
            return (String(label.dropLast(suf.count)).trimmingCharacters(in: .whitespaces), true)
        }
        return (label, false)
    }

    public static func flat(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            .replacing(/\s+/, with: " ")
    }

    static func needle(_ q: QuestionRequest.Question) -> String {
        String(flat(q.text).prefix(24)).trimmingCharacters(in: .whitespaces)
    }

    static func markers(agent: String) -> [String] {
        agent == "codex" ? ["enter to submit"] : ["Chat about this", "Review your answers"]
    }

    static func isBar(_ l: String) -> Bool {
        let t = l.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("☐") || t.hasPrefix("☒") || t.hasPrefix("✔") || t.hasPrefix("←")
    }

    public static func pickerRegion(agent: String, screen: String) -> String? {
        let lines = screen.components(separatedBy: "\n")
        let start: Int? = agent == "codex"
            ? lines.lastIndex { $0.firstMatch(of: /^\s*Question \d+\/\d+/) != nil }
            : lines.lastIndex(where: isBar)
        guard let start else { return nil }
        let region = flat(lines[start...].joined(separator: "\n"))
        return markers(agent: agent).contains { region.contains($0) } ? region : nil
    }

    public struct ScreenQuestion: Sendable, Hashable {
        public var headers: [String]
        public var question: QuestionRequest.Question
        public var typed: String?
        public var focusMarks: Int
    }

    public static func claudeParse(_ screen: String) -> ScreenQuestion? {
        let lines = screen.components(separatedBy: "\n")
        guard let end = lines.lastIndex(where: { $0.contains("Chat about this") }),
              let bar = lines[..<end].lastIndex(where: isBar) else { return nil }
        let headers = lines[bar].split(whereSeparator: { "☐☒✔←→".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "Submit" }
        let optRe = /^(\s*(?:❯\s*)?)(\d+)\.\s+(\[[ ✔]\]\s+)?(.*)$/
        var text: [String] = [], options: [QuestionRequest.Option] = []
        var multi = false, inOptions = false, closed = false, lastRaw = "", submitFocused = false
        var marks = 0, sinceRow = 0, rowColumn: Int?, strayMark = false
        for l in lines[(bar + 1)..<end] {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("──") { closed = true; break }
            let marked = t.hasPrefix("❯")
            if !t.isEmpty, submitFocused { submitFocused = false; strayMark = true; sinceRow += 1 }
            if inOptions, sinceRow == 0, marked, t.dropFirst().trimmingCharacters(in: .whitespaces) == "Submit" { submitFocused = true; marks += 1; continue }
            if let m = l.wholeMatch(of: optRe), rowColumn == nil ? m.2 == "1" && m.1.count >= 2 : m.1.count == rowColumn {
                if rowColumn == nil { rowColumn = m.1.count }
                guard Int(m.2) == options.count + 1 else { return nil }
                sinceRow = 0
                if marked { marks += 1 }
                let label = String(m.4).trimmingCharacters(in: .whitespaces)
                inOptions = true
                if m.3 != nil { multi = true }
                let (clean, rec) = stripRecommended(label)
                options.append(.init(label: clean, recommended: rec))
                lastRaw = label
            } else if inOptions {
                if marked { strayMark = true }
                if !t.isEmpty { sinceRow += 1 }
                if !t.isEmpty, !options.isEmpty { options[options.count - 1].detail += (options[options.count - 1].detail.isEmpty ? "" : " ") + t }
            } else if !t.isEmpty {
                if marked { strayMark = true }
                text.append(t)
            }
        }
        guard closed, options.popLast() != nil, !options.isEmpty, !text.isEmpty else { return nil }
        let typed: String? = lastRaw == "Type something." || lastRaw == "Type something" ? nil : lastRaw
        let q = QuestionRequest.Question(header: headers.count == 1 ? headers[0] : "", text: text.joined(separator: " "), options: options, multiSelect: multi)
        return ScreenQuestion(headers: headers, question: q, typed: typed, focusMarks: strayMark ? 0 : marks)
    }

    static func djb2(_ s: String) -> String {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return String(h, radix: 16)
    }

    public static func screenRequest(_ screen: String) -> QuestionRequest? {
        guard let s = claudeParse(screen), s.focusMarks == 1, s.typed == nil else { return nil }
        let key = ([s.headers.joined(separator: "|"), s.question.text] + s.question.options.map(\.label) + [s.question.multiSelect ? "m" : "s"]).joined(separator: "\n")
        return QuestionRequest(toolUseId: "screen-" + djb2(key), agent: "claude", questions: [s.question], headers: s.headers)
    }

    public static func showsReview(_ screen: String) -> Bool {
        pickerRegion(agent: "claude", screen: screen)?.contains("Review your answers") == true
    }

    public static func showsCodex(_ q: QuestionRequest, screen: String) -> Bool {
        guard let first = q.questions.first, let region = pickerRegion(agent: "codex", screen: screen) else { return false }
        return region.contains(needle(first))
    }

    static func otherText(_ a: QuestionAnswer) -> String? {
        let s = a.other?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    public static func steps(for q: QuestionRequest, answers: [QuestionAnswer]) throws -> [Step] {
        guard answers.count == q.questions.count else { throw Failure.unsupported("\(answers.count) answers for \(q.questions.count) questions") }
        for (k, a) in answers.enumerated() {
            let n = q.questions[k].options.count
            guard a.picks.allSatisfy({ (0..<n).contains($0) }), n <= 8 else { throw Failure.unsupported("option out of range") }
            let other = a.other?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if other.contains(where: \.isNewline) { throw Failure.unsupported("line break in the text") }
            if other.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { throw Failure.unsupported("control character in the text") }
            if ["Add notes", "Type something.", "Type something"].contains(flat(other)) { throw Failure.unsupported("this text is the field's placeholder") }
            if a.picks.isEmpty && other.isEmpty { throw Failure.unsupported("no answer") }
            if !q.questions[k].multiSelect && a.picks.count > 1 { throw Failure.unsupported("one choice only") }
        }
        return q.agent == "codex" ? try codexSteps(q, answers) : claudeSteps(q, answers)
    }

    static func claudeSteps(_ q: QuestionRequest, _ answers: [QuestionAnswer]) -> [Step] {
        var out: [Step] = []
        for (k, question) in q.questions.enumerated() {
            let a = answers[k], n = question.options.count
            if !question.multiSelect {
                if let other = otherText(a) { out += [.text("\(n + 1)"), .text(other), .keys(["enter"])] }
                else { out.append(.text("\(a.picks[0] + 1)")) }
            } else {
                for p in a.picks.sorted() { out.append(.text("\(p + 1)")) }
                if let other = otherText(a) {
                    out += [.text("\(n + 1)"), .keys(Array(repeating: "down", count: n)), .text(other), .keys(["tab"]), .keys(["enter"])]
                } else {
                    out.append(.keys(["tab"]))
                }
            }
            if k + 1 < q.questions.count { out.append(.waitFor(needle(q.questions[k + 1]))) }
        }
        return out
    }

    static func codexSteps(_ q: QuestionRequest, _ answers: [QuestionAnswer]) throws -> [Step] {
        var out: [Step] = []
        for (k, question) in q.questions.enumerated() {
            if question.multiSelect { throw Failure.unsupported("Codex has no multi-choice picker") }
            let a = answers[k], n = question.options.count
            if let other = otherText(a) {
                let row = a.picks.first ?? n
                if row > 0 { out.append(.keys(Array(repeating: "down", count: row))) }
                out += [.keys(["tab"]), .text(other), .keys(["enter"])]
            } else {
                out.append(.text("\(a.picks[0] + 1)"))
            }
            if k + 1 < q.questions.count { out.append(.waitFor(needle(q.questions[k + 1]))) }
        }
        return out
    }

    public static func messageText(for q: QuestionRequest, answers: [QuestionAnswer]) -> String {
        zip(q.questions, answers).map { question, a -> String in
            let v = (a.picks.sorted().map { question.options[$0].label } + [otherText(a)].compactMap { $0 }).joined(separator: ", ")
            return q.questions.count == 1 ? v : "\(question.text) \(v)"
        }.joined(separator: "\n")
    }
}

enum QuestionLog {
    static func claude(id: String, input: [String: Any]) -> QuestionRequest? {
        guard let qs = input["questions"] as? [[String: Any]], !qs.isEmpty else { return nil }
        let questions = qs.map { q -> QuestionRequest.Question in
            let opts = (q["options"] as? [[String: Any]] ?? []).map { o -> QuestionRequest.Option in
                let (label, rec) = Questions.stripRecommended(o["label"] as? String ?? "")
                return .init(label: label, detail: o["description"] as? String ?? "", recommended: rec)
            }
            return .init(header: q["header"] as? String ?? "", text: q["question"] as? String ?? "",
                         options: opts, multiSelect: q["multiSelect"] as? Bool ?? false)
        }
        return QuestionRequest(toolUseId: id, agent: "claude", questions: questions)
    }

    static func claudeState(_ q: QuestionRequest, isError: Bool, result: Any?, text: String) -> QuestionRequest.State {
        if isError { return .declined }
        var byQuestion: [String: String] = [:]
        if let r = result as? [String: Any], let a = r["answers"] as? [String: String] { byQuestion = a }
        else {
            for m in text.matches(of: /"((?:[^"\\]|\\.)*)"="((?:[^"\\]|\\.)*)"/) {
                func un(_ s: Substring) -> String { s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
                byQuestion[un(m.1)] = un(m.2)
            }
        }
        return answered(q.questions.map { byQuestion[$0.id] })
    }

    static let codexTools: Set<String> = ["request_user_input", "request_user_input_async"]

    static func codex(name: String, callId: String, arguments: String) -> QuestionRequest? {
        guard codexTools.contains(name), let d = arguments.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let qs = o["questions"] as? [[String: Any]], !qs.isEmpty else { return nil }
        let questions = qs.enumerated().map { k, q -> QuestionRequest.Question in
            let opts: [QuestionRequest.Option] = (q["options"] as? [Any] ?? []).compactMap { o in
                if let s = o as? String { let (l, r) = Questions.stripRecommended(s); return .init(label: l, recommended: r) }
                guard let o = o as? [String: Any] else { return nil }
                let (l, r) = Questions.stripRecommended(o["label"] as? String ?? "")
                return .init(label: l, detail: o["description"] as? String ?? "", recommended: r)
            }
            let text = q["question"] as? String ?? q["title"] as? String ?? ""
            return .init(id: q["id"] as? String ?? "q\(k)", header: q["header"] as? String ?? "", text: text,
                         options: opts, multiSelect: q["multiSelect"] as? Bool ?? q["multi_select"] as? Bool ?? false)
        }
        return QuestionRequest(toolUseId: callId, agent: "codex",
                               delivery: name == "request_user_input" ? .picker : .message, questions: questions)
    }

    static func codexState(_ q: QuestionRequest, output: String) -> QuestionRequest.State? {
        let o = output.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if q.delivery == .message, o?["accepted"] as? Bool == true { return nil }
        guard let byId = o?["answers"] as? [String: Any] else { return .declined }
        return answered(q.questions.map { question -> String? in
            guard let list = (byId[question.id] as? [String: Any])?["answers"] as? [String] else { return nil }
            let notes = list.filter { $0.hasPrefix("user_note: ") }.map { String($0.dropFirst(11)) }
            var picks = list.filter { !$0.hasPrefix("user_note: ") }
            if !notes.isEmpty { picks.removeAll { $0 == Questions.codexOtherLabel } }
            return (picks + notes).joined(separator: ", ")
        })
    }

    static func answered(_ answers: [String?]) -> QuestionRequest.State {
        guard answers.contains(where: { $0 != nil }) else { return .answered(nil) }
        return .answered(answers.map { $0 ?? "" })
    }
}
