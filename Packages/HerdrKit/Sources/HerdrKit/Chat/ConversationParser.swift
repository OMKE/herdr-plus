import Foundation

public struct ConversationParser: Sendable {
    struct ToolLabel: Sendable { var symbol: String; var singular: String; var plural: String? }
    struct RunEntry: Sendable { var tool: String; var label: ToolLabel; var id: String }

    var done: [ChatItem] = []
    var run: [RunEntry] = []
    var runKey = ""
    var openToolUses: [String: String] = [:]
    var openOrder: [String] = []
    var callTS: [String: Date] = [:]
    var lineTS: Date?
    var callById: [String: ToolCall] = [:]
    var runsByKey: [String: [RunEntry]] = [:]
    var questionAt: [String: Int] = [:]
    var thought: (id: String, message: String?, text: String)?
    var codexSeq = 0
    public private(set) var continuedIn: String?
    public private(set) var model: String?
    public private(set) var imageBlobs: [String: String] = [:]
    var blobOrder: [String] = []

    public init() {}

    public func imageData(_ key: String) -> Data? {
        imageBlobs[key].flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
    }

    mutating func keepImages(_ blocks: [[String: Any]], prefix: String) -> [String] {
        var keys: [String] = []
        for (i, b) in blocks.enumerated() {
            var data: String?
            if b["type"] as? String == "image", let src = b["source"] as? [String: Any], src["type"] as? String == "base64" {
                data = src["data"] as? String
            } else if b["type"] as? String == "input_image", let url = b["image_url"] as? String, url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") {
                data = String(url[url.index(after: comma)...])
            }
            guard let data, !data.isEmpty else { continue }
            let key = "\(prefix)#\(i)"
            if imageBlobs[key] == nil { blobOrder.append(key) }
            imageBlobs[key] = data
            keys.append(key)
        }
        while blobOrder.count > 40 { imageBlobs[blobOrder.removeFirst()] = nil }
        return keys
    }

    public var hasOpenToolUse: Bool { !openOrder.isEmpty }

    public static func parse(lines: [String]) -> ConversationParser {
        var p = ConversationParser()
        for l in lines { p.feed(line: l) }
        return p
    }

    public func items(awaitingApproval: Bool = true) -> [ChatItem] {
        var out = done.map { item -> ChatItem in
            guard item.id.hasPrefix("tools-"), let r = runsByKey[String(item.id.dropFirst(6))] else { return item }
            return Self.chips(r, key: String(item.id.dropFirst(6)), calls: callById, at: r.first.flatMap { callTS[$0.id] })
        }
        var run = self.run
        var perm: ChatItem?
        if awaitingApproval, let last = openOrder.last, let cmd = openToolUses[last], let i = run.lastIndex(where: { $0.id == last }) {
            let t = run.remove(at: i)
            perm = ChatItem(id: "perm-\(last)", kind: .permission(PermissionRequest(title: "Wants to \(Self.verb(t.tool))", command: cmd, toolName: t.tool, toolUseId: last)), timestamp: callTS[last])
        }
        if !run.isEmpty { out.append(Self.chips(run, key: runKey, calls: callById, at: run.first.flatMap { callTS[$0.id] })) }
        if let perm { out.append(perm) }
        return out
    }

    public mutating func feed(line: String) {
        autoreleasepool { feedLine(line) }
    }

    private mutating func feedLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        lineTS = Self.parseTime(o["timestamp"] as? String)
        if let payload = o["payload"] as? [String: Any] { feedCodex(type: o["type"] as? String, payload: payload); return }
        let type = o["type"] as? String
        continuedIn = type == "continued-in" ? o["continuedInSessionId"] as? String : nil
        if o["isSidechain"] as? Bool == true { return }
        if type == "attachment" { feedQueued(o); return }
        guard type == "user" || type == "assistant", let msg = o["message"] as? [String: Any] else { return }
        if type == "assistant", let m = msg["model"] as? String, !m.isEmpty, !m.hasPrefix("<") { model = m }
        let uuid = o["uuid"] as? String ?? UUID().uuidString
        let meta = o["isMeta"] as? Bool ?? false
        let compactFlag = o["isCompactSummary"] as? Bool ?? false

        var blocks: [[String: Any]] = []
        if let s = msg["content"] as? String { blocks = [["type": "text", "text": s]] }
        else if let a = msg["content"] as? [[String: Any]] { blocks = a }
        let images = type == "user" && !meta && !compactFlag ? blocks.filter { $0["type"] as? String == "image" }.count : 0
        let firstNew = done.count
        let messageId = msg["id"] as? String

        for (i, b) in blocks.enumerated() {
            let bid = "\(uuid)-\(i)"
            let kind = b["type"] as? String
            if kind == "thinking" || kind == "redacted_thinking" {
                let words = (b["thinking"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if type == "assistant", !words.isEmpty { thought = (bid, messageId, words) }
                continue
            }
            if let t = thought {
                thought = nil
                if kind == "tool_use", type == "assistant", t.message == messageId {
                    flush()
                    done.append(ChatItem(id: t.id, kind: .assistant(t.text), timestamp: lineTS))
                }
            }
            switch kind {
            case "text":
                let text = (b["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                if type == "user" {
                    if compactFlag || text.hasPrefix("This session is being continued") {
                        flush()
                        done.append(ChatItem(id: bid, kind: .status("Context compacted"), timestamp: lineTS))
                        continue
                    }
                    if meta { continue }
                    guard let shown = Self.userVisible(text) else { continue }
                    flush()
                    done.append(ChatItem(id: bid, kind: .user(shown), timestamp: lineTS))
                } else {
                    flush()
                    done.append(ChatItem(id: bid, kind: .assistant(text), timestamp: lineTS))
                }
            case "tool_use":
                guard type == "assistant" else { continue }
                let name = b["name"] as? String ?? "tool"
                let input = b["input"] as? [String: Any] ?? [:]
                let id = b["id"] as? String ?? bid
                if name == "AskUserQuestion", let q = QuestionLog.claude(id: id, input: input) {
                    flush()
                    questionAt[id] = done.count
                    done.append(ChatItem(id: "q-\(id)", kind: .question(q), timestamp: lineTS))
                    continue
                }
                if run.isEmpty { runKey = bid }
                run.append(RunEntry(tool: name, label: Self.label(for: name), id: id))
                callTS[id] = lineTS
                openToolUses[id] = Self.commandText(name: name, input: input)
                openOrder.append(id)
                callById[id] = ToolCall(id: id, toolName: name, summary: Self.summary(name: name, input: input), input: Self.cut(Self.prettyJSON(input)))
            case "tool_result":
                if let id = b["tool_use_id"] as? String, let at = questionAt[id], case .question(var q) = done[at].kind {
                    q.state = QuestionLog.claudeState(q, isError: b["is_error"] as? Bool ?? false, result: o["toolUseResult"], text: Self.resultText(b["content"]))
                    done[at].kind = .question(q)
                    questionAt[id] = nil
                } else if let id = b["tool_use_id"] as? String {
                    callById[id]?.output = Self.cut(Self.resultText(b["content"]))
                    callById[id]?.isError = b["is_error"] as? Bool ?? false
                    openToolUses[id] = nil
                    openOrder.removeAll { $0 == id }
                }
            default:
                break
            }
        }
        guard images > 0 else { return }
        let keys = keepImages(blocks, prefix: uuid)
        if let at = done[firstNew...].firstIndex(where: { if case .user = $0.kind { true } else { false } }) {
            done[at].images = images
            done[at].imageKeys = keys
        } else {
            flush()
            done.append(ChatItem(id: "\(uuid)-img", kind: .user(""), timestamp: lineTS, images: images, imageKeys: keys))
        }
    }

    private mutating func feedQueued(_ o: [String: Any]) {
        guard let a = o["attachment"] as? [String: Any], a["type"] as? String == "queued_command",
              a["commandMode"] as? String == "prompt" else { return }
        if let origin = a["origin"], (origin as? [String: Any])?["kind"] as? String != "human" { return }
        let text: String
        if let s = a["prompt"] as? String { text = s }
        else if let blocks = a["prompt"] as? [[String: Any]] {
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let shown = Self.userVisible(trimmed) else { return }
        flush()
        done.append(ChatItem(id: "\(o["uuid"] as? String ?? UUID().uuidString)-0", kind: .user(shown), timestamp: lineTS))
    }

    private mutating func feedCodex(type: String?, payload: [String: Any]) {
        if type == "turn_context", let m = payload["model"] as? String, !m.isEmpty { model = m }
        guard type == "response_item" else { return }
        codexSeq += 1
        let bid = "cx\(codexSeq)"
        switch payload["type"] as? String {
        case "message":
            let role = payload["role"] as? String
            guard role == "user" || role == "assistant" else { return }
            let content = payload["content"] as? [[String: Any]] ?? []
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let images = role == "user" ? content.filter { $0["type"] as? String == "input_image" }.count : 0
            if text.isEmpty && images == 0 { return }
            flush()
            if role == "user" {
                var shown = ""
                if !text.isEmpty {
                    guard !text.hasPrefix("# AGENTS.md"), let s = Self.userVisible(text) else { return }
                    shown = s
                }
                answerAsyncQuestions()
                done.append(ChatItem(id: bid, kind: .user(shown), timestamp: lineTS, images: images, imageKeys: images > 0 ? keepImages(content, prefix: bid) : []))
            } else {
                done.append(ChatItem(id: bid, kind: .assistant(text), timestamp: lineTS))
            }
        case "custom_tool_call", "function_call", "local_shell_call":
            let name = payload["name"] as? String ?? (payload["type"] as? String == "local_shell_call" ? "shell" : "tool")
            let id = payload["call_id"] as? String ?? bid
            if let q = QuestionLog.codex(name: name, callId: id, arguments: payload["arguments"] as? String ?? "") {
                flush()
                questionAt[id] = done.count
                done.append(ChatItem(id: "q-\(id)", kind: .question(q), timestamp: lineTS))
                return
            }
            if run.isEmpty { runKey = bid }
            run.append(RunEntry(tool: name, label: Self.codexLabel(for: name), id: id))
            callTS[id] = lineTS
            openToolUses[id] = Self.codexCommand(payload)
            openOrder.append(id)
            let raw = (payload["arguments"] as? String) ?? (payload["input"] as? String) ?? ""
            callById[id] = ToolCall(id: id, toolName: name, summary: Self.codexCommand(payload), input: Self.cut(raw))
        case "custom_tool_call_output", "function_call_output", "local_shell_call_output":
            if let id = payload["call_id"] as? String, let at = questionAt[id], case .question(var q) = done[at].kind {
                if let state = QuestionLog.codexState(q, output: Self.resultText(payload["output"])) {
                    q.state = state
                    done[at].kind = .question(q)
                }
                if q.state != .pending || q.delivery == .picker { questionAt[id] = nil }
                return
            }
            if let id = payload["call_id"] as? String {
                callById[id]?.output = Self.cut(Self.resultText(payload["output"]))
                openToolUses[id] = nil
                openOrder.removeAll { $0 == id }
            }
        default:
            break
        }
    }

    private mutating func answerAsyncQuestions() {
        for (id, at) in questionAt {
            guard case .question(var q) = done[at].kind, q.delivery == .message else { continue }
            q.state = .answered(nil)
            done[at].kind = .question(q)
            questionAt[id] = nil
        }
    }

    mutating func flush() {
        guard !run.isEmpty else { return }
        runsByKey[runKey] = run
        done.append(Self.chips(run, key: runKey, calls: callById, at: run.first.flatMap { callTS[$0.id] }))
        run = []
    }

    static func codexLabel(for tool: String) -> ToolLabel {
        switch tool {
        case "exec", "exec_command", "shell", "local_shell", "container.exec", "write_stdin":
            return ToolLabel(symbol: "terminal", singular: "Ran a command", plural: "Ran %d commands")
        case "apply_patch":
            return ToolLabel(symbol: "pencil", singular: "Edited files", plural: "Edited files %d times")
        case "web_search", "web.run":
            return ToolLabel(symbol: "globe", singular: "Searched the web", plural: "Searched the web %d times")
        case "update_plan":
            return ToolLabel(symbol: "checklist", singular: "Updated the plan", plural: nil)
        default:
            return ToolLabel(symbol: "wrench", singular: "Used \(tool)", plural: nil)
        }
    }

    static func codexCommand(_ payload: [String: Any]) -> String {
        if let args = payload["arguments"] as? String,
           let d = args.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for k in ["cmd", "command"] {
                if let s = o[k] as? String, !s.isEmpty { return s }
                if let a = o[k] as? [String], !a.isEmpty { return a.joined(separator: " ") }
            }
        }
        if let input = payload["input"] as? String, !input.isEmpty {
            return String(String(input.split(separator: "\n").first ?? "").prefix(200))
        }
        return payload["name"] as? String ?? "tool"
    }

    static func parseTime(_ s: String?) -> Date? {
        guard let s else { return nil }
        return (try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(s, strategy: Date.ISO8601FormatStyle()))
    }

    static func chips(_ run: [RunEntry], key: String, calls: [String: ToolCall], at: Date? = nil) -> ChatItem {
        var order: [String] = []
        var counts: [String: Int] = [:]
        var labels: [String: ToolLabel] = [:]
        var groups: [String: [ToolCall]] = [:]
        for r in run {
            let k = r.label.singular
            if counts[k] == nil { order.append(k); labels[k] = r.label }
            counts[k, default: 0] += 1
            if let c = calls[r.id] { groups[k, default: []].append(c) }
        }
        let chips = order.map { k -> ToolChip in
            let l = labels[k]!, n = counts[k]!
            let text = (n > 1 ? l.plural.map { String(format: $0, n) } : nil) ?? l.singular
            return ToolChip(id: "\(key)|\(k)", symbol: l.symbol, text: text, calls: groups[k] ?? [])
        }
        return ChatItem(id: "tools-\(key)", kind: .tools(chips), timestamp: at)
    }

    static func label(for tool: String) -> ToolLabel {
        switch tool {
        case "Read": return ToolLabel(symbol: "doc.text", singular: "Read a file", plural: "Read %d files")
        case "Edit", "MultiEdit", "NotebookEdit": return ToolLabel(symbol: "pencil", singular: "Edited a file", plural: "Edited %d files")
        case "Write": return ToolLabel(symbol: "square.and.pencil", singular: "Wrote a file", plural: "Wrote %d files")
        case "Bash", "BashOutput", "Monitor": return ToolLabel(symbol: "terminal", singular: "Ran a command", plural: "Ran %d commands")
        case "Grep", "Glob": return ToolLabel(symbol: "magnifyingglass", singular: "Searched the code", plural: "Searched the code %d times")
        case "WebFetch", "WebSearch": return ToolLabel(symbol: "globe", singular: "Searched the web", plural: "Searched the web %d times")
        case "Agent", "Task": return ToolLabel(symbol: "person.2", singular: "Delegated a task", plural: "Delegated %d tasks")
        case "TodoWrite": return ToolLabel(symbol: "checklist", singular: "Updated the to-do list", plural: nil)
        default:
            if tool.hasPrefix("mcp__") { return ToolLabel(symbol: "puzzlepiece.extension", singular: "Used a connector", plural: "Used connectors %d times") }
            return ToolLabel(symbol: "wrench", singular: "Used \(tool)", plural: nil)
        }
    }

    static func verb(_ tool: String) -> String {
        switch tool {
        case "Bash": "run a command"
        case "Edit", "MultiEdit", "NotebookEdit": "edit a file"
        case "Write": "write a file"
        case "Read": "read a file"
        case "WebFetch", "WebSearch": "use the web"
        default: "use \(tool)"
        }
    }

    static let maxDetail = 4096

    static func cut(_ s: String) -> String {
        guard s.utf8.count > maxDetail else { return s }
        var i = s.utf8.index(s.utf8.startIndex, offsetBy: maxDetail)
        while i > s.startIndex, i.samePosition(in: s) == nil { i = s.utf8.index(before: i) }
        return String(s[..<i]) + "…"
    }

    static func prettyJSON(_ o: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(o),
              let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }

    static func resultText(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let a = v as? [[String: Any]] { return a.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        return ""
    }

    static func summary(name: String, input: [String: Any]) -> String {
        let keys: [String]
        switch name {
        case "Bash": keys = ["command"]
        case "Read", "Write", "Edit", "MultiEdit": keys = ["file_path", "path"]
        case "NotebookEdit": keys = ["notebook_path", "file_path"]
        case "Task", "Agent": keys = ["description", "prompt"]
        default: keys = []
        }
        for k in keys { if let s = input[k] as? String, !s.isEmpty { return s } }
        for k in input.keys.sorted() { if let s = input[k] as? String, !s.isEmpty { return s } }
        return name
    }

    static func commandText(name: String, input: [String: Any]) -> String {
        for k in ["command", "file_path", "path", "url", "query", "pattern", "description"] {
            if let s = input[k] as? String, !s.isEmpty { return s }
        }
        return name
    }

    static let visibleTags: Set<String> = ["pasted_content", "hc"]

    public static func userVisible(_ text: String) -> String? {
        if text.hasPrefix("<") {
            guard let m = text.firstMatch(of: /^<([A-Za-z_][\w-]*)/), visibleTags.contains(String(m.1)) else { return nil }
        } else if text.hasPrefix("[Request interrupted") || text.hasPrefix("Caveat:") {
            return nil
        }
        guard text.contains("<pasted_content") else { return text }
        let out = unwrapPasted(text)
        return out.isEmpty ? nil : out
    }

    static func unwrapPasted(_ text: String) -> String {
        var parts: [Substring] = []
        var rest = text[...]
        while let open = rest.firstMatch(of: /<pasted_content(?: id="([^"]*)")?>/) {
            parts.append(rest[..<open.range.lowerBound])
            let close = open.1.map { "</pasted_content id=\"\($0)\">" } ?? "</pasted_content>"
            let body = rest[open.range.upperBound...]
            if let c = body.range(of: close) {
                parts.append(body[..<c.lowerBound])
                rest = body[c.upperBound...]
            } else {
                parts.append(body)
                rest = ""
            }
        }
        parts.append(rest)
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public static func hcNote(_ text: String) -> (from: String, text: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = t.wholeMatch(of: /<hc((?:\s+[\w-]+="[^"]*")*)\s*>(.*)<\/hc>/.dotMatchesNewlines()), !m.2.contains("</hc>") else { return nil }
        let from = m.1.firstMatch(of: /\sfrom="([^"]*)"/).map { String($0.1) } ?? ""
        return (from, String(m.2).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
