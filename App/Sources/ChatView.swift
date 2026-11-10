import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import HerdrKit

struct ChatView: View {
    let chat: ChatController
    var space: Space?
    var tab: SpaceTab?
    var isPad = false
    var selectedPane: String?
    @Environment(AppModel.self) private var model
    @State private var atBottom = true

    var body: some View {
        messages
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 6) {
                    ChatHeader(chat: chat, tab: tab, isPad: isPad)
                    if let space, let tab, tab.panes.count > 1 {
                        PaneSwitcher(space: space, tab: tab, selected: selectedPane)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let n = chat.notice {
                        NoticeBanner(text: n) { chat.notice = nil }
                    }
                    if let p = chat.panel {
                        PanelCard(chat: chat, panel: p)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let card = chat.card {
                        CardView(chat: chat, card: card)
                            .id(cardID(card))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Composer(chat: chat)
                }
            }
            .background(Theme.terminal)
            .animation(.easeOut(duration: 0.18), value: chat.card)
            .animation(.easeOut(duration: 0.18), value: chat.panel == nil)
            .task(id: chat.address) {
                chat.appear()
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
                chat.disappear()
            }
    }

    private func cardID(_ c: ChatCard) -> String {
        switch c {
        case .approval(let a): "a-\(a.id)"
        case .question(let q): "q-\(q.toolUseId)"
        case .review: "review"
        }
    }

    private var agentName: String {
        chat.terminal.map { model.programs.displayName(for: $0) } ?? "Agent"
    }

    private var agentColor: Color {
        guard let t = chat.terminal, let k = Locator.agentKind(t) else { return Theme.muted }
        return k == .claude ? Theme.claude : Theme.text
    }

    private func startsTurn(_ i: Int) -> Bool {
        switch chat.rows[i].kind {
        case .assistant, .tools: break
        default: return false
        }
        var j = i - 1
        while j >= 0 {
            switch chat.rows[j].kind {
            case .separator: j -= 1
            case .user, .footer: return true
            default: return false
            }
        }
        return true
    }

    private var liveToolsID: String? {
        guard let s = chat.terminal?.agentState, s == .working || s == .blocked else { return nil }
        for r in chat.rows.reversed() {
            if case .tools = r.kind { return r.id }
            if case .user = r.kind { return nil }
        }
        return nil
    }

    @ViewBuilder
    private var messages: some View {
        switch chat.phase {
        case .locating where chat.rows.isEmpty:
            VStack(spacing: 10) {
                ProgressView().tint(Theme.muted)
                Text("Finding the session…").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noLog(let msg) where chat.rows.isEmpty:
            VStack(spacing: 12) {
                Image(systemName: "text.bubble").font(.system(size: 30)).foregroundStyle(Theme.dim)
                Text(msg).font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
                Button("Try again") { chat.refresh() }.foregroundStyle(Theme.amber)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            let live = liveToolsID
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.canLoadEarlier {
                            Button {
                                Task { await chat.loadEarlier() }
                            } label: {
                                HStack(spacing: 6) {
                                    if chat.loadingEarlier { ProgressView().controlSize(.mini).tint(Theme.muted) }
                                    Text(chat.loadingEarlier ? "Loading earlier messages…" : "Load earlier messages")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Theme.raised))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(chat.loadingEarlier)
                        }
                        ForEach(Array(chat.rows.enumerated()), id: \.element.id) { i, row in
                            if startsTurn(i) {
                                AgentLine(name: agentName, color: agentColor, time: row.timestamp)
                            }
                            RowView(row: row, chat: chat, live: row.id == live).id(row.id)
                        }
                        if chat.showsWorking {
                            WorkingRow(since: chat.terminal?.statusMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }, activity: chat.activity) {
                                Task { await chat.interrupt() }
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .id(chat.logID)
                .simultaneousGesture(TapGesture().onEnded {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                })
                .onChange(of: chat.rows.last?.id) { _, _ in
                    if atBottom { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                .overlay(alignment: .bottom) {
                    if !atBottom {
                        Button {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold))
                                Text("Latest").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassCard(16)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }
}

enum ChatTime {
    static func clock(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    static func elapsed(_ s: TimeInterval) -> String {
        let n = max(0, Int(s))
        if n < 60 { return "\(n)s" }
        if n < 3600 { return "\(n / 60)m \(n % 60)s" }
        return "\(n / 3600)h \(n % 3600 / 60)m"
    }

    static func timer(_ s: TimeInterval) -> String {
        let n = max(0, Int(s))
        return n < 3600 ? String(format: "%d:%02d", n / 60, n % 60) : String(format: "%d:%02d:%02d", n / 3600, n % 3600 / 60, n % 60)
    }
}

struct AgentLine: View {
    let name: String
    let color: Color
    let time: Date?

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 11, height: 11)
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            if let time {
                Text(ChatTime.clock(time)).font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, -4)
    }
}

struct NoticeBanner: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Theme.amber)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(3)
            Spacer(minLength: 0)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.amberBg))
        .glassCard(12)
        .padding(.horizontal, 10)
        .task {
            try? await Task.sleep(for: .seconds(6))
            close()
        }
    }
}

struct WorkingRow: View {
    let since: Date?
    var activity: ScreenActivity?
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).tint(Theme.amber)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 6) {
                    Text(activity?.label ?? "Working")
                        .font(Typo.chat(14).weight(.medium))
                        .foregroundStyle(Theme.amber)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: activity?.label)
                    if let d = activity?.detail ?? since.map({ ChatTime.elapsed(ctx.date.timeIntervalSince($0)) }) {
                        Text(d)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Button(action: stop) {
                Text("esc to stop").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct RowView: View {
    let row: ChatRow
    let chat: ChatController
    var live = false

    var body: some View {
        switch row.kind {
        case .user(let text, let from):
            UserBubble(row: row, text: text, from: from, chat: chat)
        case .assistant(let text):
            MarkdownText(text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tools(let chips):
            ToolCardView(chips: chips, chat: chat, live: live)
        case .permission(let p):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.amber).font(.system(size: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.amber)
                    Text(p.command).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(4)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
        case .question(let q):
            QuestionLogView(q: q)
        case .status(let s):
            Text(s)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        case .separator(let s):
            HStack(spacing: 8) {
                Rectangle().fill(Theme.border).frame(height: 1)
                Text(s).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim).fixedSize()
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .padding(.vertical, 4)
        case .footer(let s):
            DoneFooter(text: s)
        }
    }
}

struct DoneFooter: View {
    let text: String

    var body: some View {
        let worked = text.components(separatedBy: " · ").first { $0.hasPrefix("Worked ") }
        HStack(spacing: 6) {
            Circle().fill(Theme.green).frame(width: 6, height: 6)
            Text("Done" + (worked.map { " · worked " + $0.dropFirst("Worked ".count) } ?? ""))
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
    }
}

struct UserBubble: View {
    let row: ChatRow
    let text: String
    let from: String?
    let chat: ChatController

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 5) {
                if let from, !from.isEmpty {
                    Text(from).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.dim)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if row.images > 0 || !row.imageKeys.isEmpty {
                        thumbs
                    }
                    if !text.isEmpty {
                        Text(text)
                            .font(Typo.chat(15))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
                .opacity(row.pending ? 0.6 : 1)
                if row.pending {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.dotted").font(.system(size: 10, weight: .semibold))
                        Text("Sending…")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                } else if let ts = row.timestamp {
                    Text(ChatTime.clock(ts)).font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var thumbs: some View {
        let keys = row.imageKeys
        let extra = max(0, row.images - keys.count)
        return FlowLayout(spacing: 6) {
            ForEach(keys, id: \.self) { k in
                if let img = chat.image(k) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
                } else {
                    placeholder
                }
            }
            ForEach(0..<extra, id: \.self) { _ in placeholder }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.chromeDeep)
            .frame(width: 84, height: 62)
            .overlay(Image(systemName: "photo").foregroundStyle(Theme.dim))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
    }
}

@MainActor
enum ToolMeta {
    static func name(_ c: ToolCall) -> String {
        if c.toolName.hasPrefix("mcp__") { return c.toolName.split(separator: "__").last.map(String.init) ?? c.toolName }
        return c.toolName
    }

    static func glyph(_ c: ToolCall) -> String {
        switch c.toolName {
        case "Read": "≡"
        case "Edit", "MultiEdit", "Write", "NotebookEdit": "±"
        case "Bash", "BashOutput", "Monitor", "shell", "exec_command", "local_shell_call": ">_"
        case "Grep", "Glob": "⌕"
        case "WebFetch", "WebSearch": "◎"
        case "Agent", "Task": "◇"
        case "TodoWrite": "☐"
        default: c.toolName.hasPrefix("mcp__") ? "⧉" : "•"
        }
    }

    static func json(_ c: ToolCall) -> [String: Any]? {
        guard let d = c.input.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func target(_ c: ToolCall, cwd: String?) -> String {
        let j = json(c)
        var s: String
        switch c.toolName {
        case "Grep":
            let p = j?["pattern"] as? String ?? c.summary
            let path = j?["path"] as? String
            s = "\"\(p)\"" + (path.map { " " + $0 } ?? "")
        case "Glob": s = j?["pattern"] as? String ?? c.summary
        case "WebSearch": s = j?["query"] as? String ?? c.summary
        case "WebFetch": s = j?["url"] as? String ?? c.summary
        default: s = c.summary
        }
        if let cwd, !cwd.isEmpty {
            s = s.replacingOccurrences(of: cwd.hasSuffix("/") ? cwd : cwd + "/", with: "")
        }
        if let m = s.firstMatch(of: /\/Users\/[^\/\s]+\//) { s = s.replacingOccurrences(of: String(m.0), with: "~/") }
        return s.replacingOccurrences(of: "\n", with: " ")
    }

    static func lines(_ s: String) -> Int {
        s.isEmpty ? 0 : s.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func details(_ c: ToolCall) -> [(String, Color)] {
        let out = c.output ?? ""
        let capped = out.hasSuffix("…")
        if c.isError {
            if let m = out.firstMatch(of: /Exit code (\d+)/) { return [("exit \(m.1)", Theme.red)] }
            return [("error", Theme.red)]
        }
        guard c.isDone else { return [] }
        switch c.toolName {
        case "Edit":
            guard let j = json(c) else { return [] }
            return diff(j["old_string"] as? String ?? "", j["new_string"] as? String ?? "")
        case "MultiEdit":
            guard let edits = json(c)?["edits"] as? [[String: Any]] else { return [] }
            var a = 0, r = 0
            for e in edits {
                a += lines(e["new_string"] as? String ?? "")
                r += lines(e["old_string"] as? String ?? "")
            }
            return [("+\(a)", Theme.green), ("-\(r)", Theme.red)]
        case "Write":
            guard let content = json(c)?["content"] as? String else { return [] }
            return [("+\(lines(content))", Theme.green)]
        case "Grep":
            if let m = out.firstMatch(of: /Found (\d+) (file|files|match|matches|line|lines)/) { return [("\(m.1) \(m.2 == "file" || m.2 == "files" ? "files" : "hits")", Theme.dim)] }
            return capped ? [] : [("\(lines(out.trimmingCharacters(in: .whitespacesAndNewlines))) hits", Theme.dim)]
        case "Glob":
            return capped ? [] : [("\(lines(out.trimmingCharacters(in: .whitespacesAndNewlines))) files", Theme.dim)]
        case "Read":
            return capped ? [] : [("\(lines(out.trimmingCharacters(in: .newlines))) lines", Theme.dim)]
        default:
            return []
        }
    }

    static func diff(_ old: String, _ new: String) -> [(String, Color)] {
        let o = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let n = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var p = 0
        while p < o.count, p < n.count, o[p] == n[p] { p += 1 }
        var s = 0
        while s < o.count - p, s < n.count - p, o[o.count - 1 - s] == n[n.count - 1 - s] { s += 1 }
        let removed = old.isEmpty ? 0 : o.count - p - s
        let added = new.isEmpty ? 0 : n.count - p - s
        return [("+\(added)", Theme.green), ("-\(removed)", Theme.red)]
    }
}

struct ToolCardView: View {
    let chips: [ToolChip]
    let chat: ChatController
    var live = false
    @State private var open: Set<String> = []

    var body: some View {
        let calls = chips.flatMap(\.calls)
        let waitingID = live && chat.terminal?.agentState == .blocked ? calls.last(where: { !$0.isDone })?.id : nil
        let running = live && calls.contains { !$0.isDone }
        VStack(alignment: .leading, spacing: 0) {
            Text(calls.isEmpty ? chips.map(\.text).joined(separator: " · ") : "\(calls.count) \(calls.count == 1 ? "tool" : "tools")" + (running ? " · running" : ""))
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            ForEach(calls, id: \.id) { c in
                Rectangle().fill(Theme.border.opacity(0.7)).frame(height: 0.75)
                row(c, waiting: c.id == waitingID, running: live && !c.isDone && c.id != waitingID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chromeDeep.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border))
    }

    @ViewBuilder
    private func row(_ c: ToolCall, waiting: Bool, running: Bool) -> some View {
        let isOpen = open.contains(c.id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { open.remove(c.id) } else { open.insert(c.id) }
                }
            } label: {
                HStack(spacing: 9) {
                    Text(ToolMeta.glyph(c))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised))
                    Text(ToolMeta.name(c))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize()
                    Text(ToolMeta.target(c, cwd: chat.terminal?.foreground?.cwd ?? chat.terminal?.cwd))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    ForEach(Array(ToolMeta.details(c).enumerated()), id: \.offset) { _, d in
                        Text(d.0).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(d.1).fixedSize()
                    }
                    status(c, waiting: waiting, running: running)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                let body = (c.output?.isEmpty == false ? c.output : nil) ?? c.input
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(body)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(c.isError ? Theme.red.opacity(0.9) : Theme.muted)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.terminal.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.border))
                .padding(.leading, 45)
                .padding(.trailing, 12)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private func status(_ c: ToolCall, waiting: Bool, running: Bool) -> some View {
        if waiting {
            HStack(spacing: 5) {
                Text("needs you").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.amber).fixedSize()
                Circle().fill(Theme.amber).frame(width: 7, height: 7)
            }
        } else if running {
            ProgressView().controlSize(.mini).tint(Theme.muted)
        } else if c.isDone {
            Image(systemName: c.isError ? "xmark" : "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(c.isError ? Theme.red : Theme.green)
        } else {
            Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim)
        }
    }
}

struct QuestionLogView: View {
    let q: QuestionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(q.questions.enumerated()), id: \.offset) { i, question in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle").font(.system(size: 12)).foregroundStyle(Theme.blue)
                        Text(question.text).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
                    }
                    switch q.state {
                    case .answered(let a?) where a.indices.contains(i) && !a[i].isEmpty:
                        Text(a[i]).font(.system(size: 13)).foregroundStyle(Theme.green)
                    case .declined:
                        Text("Declined").font(.system(size: 13)).foregroundStyle(Theme.dim)
                    case .pending:
                        Text(question.options.map(\.label).joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    default:
                        Text("Answered").font(.system(size: 13)).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
    }
}

struct PanelCard: View {
    let chat: ChatController
    let panel: TUIPanel

    private let keys: [(String, String)] = [("↑", "up"), ("↓", "down"), ("←", "left"), ("→", "right"), ("tab", "tab"), ("⏎", "enter"), ("esc", "esc")]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "terminal").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.amber)
                Text(panel.command).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                Spacer()
                Button("Done") { Task { await chat.closePanel() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .accessibilityIdentifier("panel-done")
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    Group {
                        if panel.screen.isEmpty {
                            ProgressView().tint(Theme.muted).frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            Text(panel.screen)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .fixedSize()
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                    .id("panel-end")
                }
                .frame(maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.terminal))
                .defaultScrollAnchor(.bottomLeading)
                .onChange(of: panel.screen) { _, _ in proxy.scrollTo("panel-end", anchor: .bottomLeading) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(keys, id: \.1) { k in
                        Button(k.0) { Task { await chat.panelKey(k.1) } }
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
                            .buttonStyle(.plain)
                    }
                }
            }
            Text("This command opens a panel in the terminal. It isn't saved in the chat log, so it shows here live.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
        }
        .padding(14)
        .amberCard()
        .padding(.horizontal, 8)
    }
}

struct CardView: View {
    let chat: ChatController
    let card: ChatCard

    var body: some View {
        Group {
            switch card {
            case .approval(let a):
                ApprovalCardView(chat: chat, card: a)
            case .question(let q):
                QuestionCardView(chat: chat, q: q)
            case .review(let title):
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Circle().fill(Theme.amber).frame(width: 7, height: 7)
                        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    }
                    Text("Check the answers in the terminal, or submit them now.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    PrimaryButton(title: "Submit answers", busy: chat.busy) { Task { await chat.submitReview() } }
                }
                .padding(14)
                .amberCard()
            }
        }
        .padding(.horizontal, 8)
    }
}

struct HintBadge: View {
    let text: String
    var onAccent = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(onAccent ? Theme.onAccent.opacity(0.75) : Theme.dim)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(onAccent ? Theme.onAccent.opacity(0.12) : Theme.raised))
    }
}

struct PrimaryButton: View {
    let title: String
    var tint: Color = Theme.amber
    var filled = true
    var hint: String?
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                if busy && filled { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                Text(title).font(.system(size: 15, weight: .semibold))
                if let hint { HintBadge(text: hint, onAccent: filled) }
            }
            .foregroundStyle(filled ? Theme.onAccent : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(filled ? tint : Theme.chromeDeep))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(filled ? .clear : Theme.border))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

struct ApprovalCardView: View {
    let chat: ChatController
    let card: ApprovalCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Theme.amber).frame(width: 7, height: 7)
                Text(card.clipped ? "Approval needed" : card.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer(minLength: 6)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text([card.tool.isEmpty ? nil : card.tool, since.map { ChatTime.timer(ctx.date.timeIntervalSince($0)) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .monospacedDigit()
                }
            }
            if card.clipped {
                Text(card.title).font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else if !card.command.isEmpty {
                ScrollView {
                    Text(card.command)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.terminal.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border))
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Deny", filled: false, hint: "3", busy: chat.busy) { Task { await chat.approve(card, allow: false) } }
                PrimaryButton(title: "Allow", hint: "1", busy: chat.busy) { Task { await chat.approve(card, allow: true) } }
            }
            if let always = chat.alwaysLabel {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await chat.approveAlways(card) }
                } label: {
                    HStack(spacing: 8) {
                        Text(always).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        HintBadge(text: "2")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(chat.busy)
            }
        }
        .padding(14)
        .amberCard()
    }

    private var since: Date? {
        chat.terminal?.statusMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }
}

struct QuestionCardView: View {
    let chat: ChatController
    let q: QuestionRequest
    @Environment(AppModel.self) private var model
    @State private var index = 0
    @State private var picks: [Set<Int>] = []
    @State private var others: [String] = []

    var body: some View {
        let k = min(index, q.questions.count - 1)
        let question = q.questions[k]
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Theme.amber).frame(width: 7, height: 7)
                Text((chat.terminal.map { model.programs.displayName(for: $0) } ?? "Agent") + " asks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                if !question.header.isEmpty {
                    Text("· " + question.header).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer()
                if q.questions.count > 1 {
                    Text("\(k + 1) of \(q.questions.count)").font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
            Text(question.text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { i, o in
                        optionRow(k: k, i: i, o: o, multi: question.multiSelect)
                    }
                }
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Or type your own answer below").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    next()
                } label: {
                    HStack(spacing: 6) {
                        if chat.busy { ProgressView().controlSize(.small).tint(Theme.onAccent) }
                        Text(k + 1 < q.questions.count ? "Next" : "Send")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.amber))
                }
                .buttonStyle(.plain)
                .disabled(!answered(k) || chat.busy)
                .opacity(answered(k) ? 1 : 0.5)
            }
        }
        .padding(14)
        .amberCard()
        .onAppear {
            picks = Array(repeating: [], count: q.questions.count)
            others = Array(repeating: "", count: q.questions.count)
            chat.questionOther = ""
        }
        .onChange(of: chat.questionOther) { _, v in
            guard picks.indices.contains(k), !v.trimmingCharacters(in: .whitespaces).isEmpty, !q.questions[k].multiSelect else { return }
            picks[k] = []
        }
        .onChange(of: chat.questionSubmit) { _, _ in
            if answered(k) { next() }
        }
    }

    private func next() {
        let k = min(index, q.questions.count - 1)
        guard answered(k), others.indices.contains(k) else { return }
        others[k] = chat.questionOther.trimmingCharacters(in: .whitespacesAndNewlines)
        if k + 1 < q.questions.count {
            index = k + 1
            chat.questionOther = others[k + 1]
        } else {
            let a = answers()
            chat.questionOther = ""
            Task { await chat.answer(q, a) }
        }
    }

    private func optionRow(k: Int, i: Int, o: QuestionRequest.Option, multi: Bool) -> some View {
        let on = picks.indices.contains(k) && picks[k].contains(i)
        return Button {
            guard picks.indices.contains(k) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if multi {
                if on { picks[k].remove(i) } else { picks[k].insert(i) }
            } else {
                picks[k] = [i]
                chat.questionOther = ""
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(multi ? (on ? "✓" : "\(i + 1)") : "\(i + 1)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(on ? Theme.onAccent : Theme.amber)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Theme.amber : Theme.amberBg))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(o.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        if o.recommended {
                            Text("Recommended").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.amber)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.amberBg))
                        }
                    }
                    if !o.detail.isEmpty {
                        Text(o.detail).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? Theme.amberBg : Theme.chromeDeep.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(on ? Theme.amber : Theme.border, lineWidth: on ? 1.2 : 0.75))
        }
        .buttonStyle(.plain)
    }

    private func answered(_ k: Int) -> Bool {
        guard picks.indices.contains(k) else { return false }
        return !picks[k].isEmpty || !chat.questionOther.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func answers() -> [QuestionAnswer] {
        q.questions.indices.map { k in
            let o = others.indices.contains(k) ? others[k] : ""
            return QuestionAnswer(picks: picks.indices.contains(k) ? picks[k].sorted() : [], other: o.isEmpty ? nil : o)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width + 0.5 { x = 0; y += line + spacing; line = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: s))
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            line = max(line, s.height)
        }
        return (frames, CGSize(width: maxX, height: y + line))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let r = arrange(width, subviews)
        return CGSize(width: width.isFinite ? min(width, r.size.width) : r.size.width, height: r.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(proposal.width ?? bounds.width, subviews)
        for (v, f) in zip(subviews, r.frames) {
            v.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
}
