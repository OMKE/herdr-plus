import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import HerdrKit

extension View {
    func glassCard(_ radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.chrome.opacity(0.55))
            }
        }
        .overlay(shape.stroke(Theme.border.opacity(0.9), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
    }

    @ViewBuilder
    func barChrome(_ style: BarStyle, radius: CGFloat, edge: VerticalEdge) -> some View {
        if style == .floating {
            glassCard(radius).padding(.horizontal, 8)
        } else {
            background(Theme.chrome.ignoresSafeArea(edges: edge == .top ? .top : .bottom))
                .overlay(alignment: edge == .top ? .bottom : .top) { Rectangle().fill(Theme.border).frame(height: 0.75) }
        }
    }

    func amberCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Theme.chrome.opacity(0.6))
                shape.fill(Theme.amberBg)
            }
        }
        .overlay(shape.stroke(Theme.amberBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
    }
}

struct ChatHeader: View {
    let chat: ChatController
    let tab: SpaceTab?
    let isPad: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = chat.terminal?.agentState
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if !isPad {
                    Button {
                        withAnimation(.easeOut(duration: 0.22)) { model.drawerOpen = true }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .frame(width: 34, height: 34)
                            .overlay(alignment: .topTrailing) {
                                if model.needsYou.count > 0 {
                                    Text("\(model.needsYou.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.onAccent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Theme.amber))
                                        .offset(x: 4, y: -3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                ProgramIcon(program: chat.terminal.flatMap { model.programs.program(for: $0) }, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    BarTitle(title: title, blocked: state == .blocked) {
                        if let state {
                            Circle().fill(state == .working ? Theme.blue : state == .error ? Theme.red : Theme.green).frame(width: 7, height: 7)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                WorkspaceMenuButton(terminal: chat.terminal)
                Button {
                    model.showOverview = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(.plain)
                if let tab {
                    ChatModeSwitch(chat: true) { model.setChat($0, tabID: tab.id) }
                }
            }
            if let u = chat.usage, u.contextPercent != nil || u.fiveHour != nil || u.sevenDay != nil {
                UsageMeter(usage: u)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .barChrome(model.settings.topBar, radius: 20, edge: .top)
        .padding(.top, model.settings.topBar == .floating ? 4 : 0)
    }

    private var title: String {
        if let tab, !tab.name.isEmpty { return tab.name }
        return chat.terminal.map { model.programs.displayName(for: $0) } ?? "Chat"
    }

    private var subtitle: String {
        let name = chat.terminal.map { model.programs.displayName(for: $0) }
        let m = chat.usage?.model ?? chat.model.map(Self.prettyModel)
        return [name, m, chat.branch].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func prettyModel(_ raw: String) -> String {
        var s = raw.hasPrefix("claude-") ? String(raw.dropFirst(7)) : raw
        if let m = s.firstMatch(of: /-\d{8}$/) { s.removeSubrange(m.range) }
        let parts = s.split(separator: "-").map(String.init)
        guard let first = parts.first, first.allSatisfy(\.isLetter) else { return s }
        let nums = parts.dropFirst().filter { $0.allSatisfy(\.isNumber) }
        return first.capitalized + (nums.isEmpty ? "" : " " + nums.joined(separator: "."))
    }
}

struct ChatModeSwitch: View {
    var chat = true
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button {
                guard !chat else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                set(true)
            } label: {
                Text("Chat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(chat ? Theme.text : Theme.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(chat ? Theme.selectedStrong : .clear))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chat")
            Button {
                guard chat else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                set(false)
            } label: {
                Text(">_")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(chat ? Theme.muted : Theme.text)
                    .frame(width: 34, height: 28)
                    .background(Capsule().fill(chat ? .clear : Theme.selectedStrong))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Terminal")
        }
        .padding(2)
        .background(Capsule().fill(Theme.chromeDeep.opacity(0.7)))
        .overlay(Capsule().stroke(Theme.border))
        .fixedSize()
    }
}

struct UsageMeter: View {
    let usage: AgentUsage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(resets: true)
            row(resets: false)
        }
    }

    private func row(resets: Bool) -> some View {
        HStack(spacing: 12) {
            if let c = usage.contextPercent { meter("Context", c, nil) }
            if let f = usage.fiveHour { meter("5h", f.percent, resets ? f.resetsAt : nil) }
            if let s = usage.sevenDay { meter("7d", s.percent, resets ? s.resetsAt : nil) }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }

    private func meter(_ label: String, _ p: Double, _ reset: Date?) -> some View {
        let hot = p >= 75
        return HStack(spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.dim)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(hot ? Theme.amber : Theme.muted).frame(width: 26 * min(1, max(0, p / 100)))
            }
            .frame(width: 26, height: 4)
            Text("\(Int(p.rounded()))%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(hot ? Theme.amber : Theme.text)
            if let reset {
                Text("↻ " + Self.resetText(reset)).font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
        }
        .fixedSize()
    }

    static func resetText(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened).lowercased() }
        return d.formatted(.dateTime.weekday(.abbreviated))
    }
}

struct SlashPopup: View {
    let query: String
    let matches: [SlashCommand]
    let pick: (SlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Commands")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(Array(matches.enumerated()), id: \.element.id) { i, c in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pick(c)
                } label: {
                    HStack(spacing: 10) {
                        name(c.name)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize()
                        Text(detail(c))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if i == 0 {
                            Text("tab").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(i == 0 ? Theme.selected : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
        .glassCard(18)
        .padding(.horizontal, 8)
    }

    private func name(_ n: String) -> Text {
        let q = query.lowercased()
        if !q.isEmpty, n.lowercased().hasPrefix(q) {
            return Text("/" + n.prefix(q.count)).foregroundColor(Theme.amber) + Text(String(n.dropFirst(q.count))).foregroundColor(Theme.text)
        }
        return Text("/" + n).foregroundColor(Theme.text)
    }

    private func detail(_ c: SlashCommand) -> String {
        if !c.detail.isEmpty { return c.detail }
        switch c.source {
        case .project: return "Project command"
        case .user: return "User command"
        case .plugin: return "Plugin command"
        case .skill: return "Skill"
        case .builtin: return ""
        }
    }
}

struct QueuedStack: View {
    let chat: ChatController
    let agent: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 11, weight: .semibold))
                Text(chat.agentBusy ? "Queued · sends when \(agent) is done" : "Sending queued messages…")
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            ForEach(chat.queue) { m in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !m.text.isEmpty {
                            Text(m.text).font(.system(size: 14)).foregroundStyle(Theme.text).lineLimit(3)
                        }
                        if !m.images.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(m.images) { img in
                                    Image(uiImage: img.thumb).resizable().scaledToFill()
                                        .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    icon("pencil", "Edit", id: "queued-edit") { chat.editQueued(m.id) }
                    icon("paperplane.fill", "Send now", id: "queued-send-now", tint: Theme.amber) { Task { await chat.sendNow(m.id) } }
                    icon("xmark", "Cancel", id: "queued-cancel") { chat.cancelQueued(m.id) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }

    private func icon(_ symbol: String, _ label: String, id: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint ?? Theme.muted)
                .frame(width: 30, height: 30).background(Circle().fill(Theme.chromeDeep))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .disabled(chat.sending)
    }
}

struct Composer: View {
    let chat: ChatController
    @Environment(AppModel.self) private var model
    @State private var items: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var clipboardImage = UIPasteboard.general.hasImages
    @State private var focus = 0
    @State private var editKeys = false
    @State private var dictBase: String?

    private var dict: Dictation { Dictation.shared }

    private var question: Bool {
        if case .question = chat.card { return true }
        return false
    }

    private var answering: Bool { chat.card != nil }

    private var text: String {
        get { question ? chat.questionOther : chat.draft }
        nonmutating set { if question { chat.questionOther = newValue } else { chat.draft = newValue } }
    }

    private var textBinding: Binding<String> {
        Binding(get: { text }, set: { text = $0 })
    }

    private var slashQuery: String? {
        guard chat.draftCommand == nil, !question, chat.draft.hasPrefix("/"),
              !chat.draft.contains(" "), !chat.draft.contains("\n") else { return nil }
        return String(chat.draft.dropFirst())
    }

    private var matches: [SlashCommand] {
        slashQuery.map { SlashCommands.matches($0, in: chat.commands, limit: 6) } ?? []
    }

    private var agentName: String {
        chat.terminal.map { model.programs.displayName(for: $0) } ?? "agent"
    }

    private var placeholder: String {
        if question { return "Other answer…" }
        if chat.draftCommand != nil { return "Arguments (optional)" }
        return "Message \(agentName)"
    }

    private var stripKeys: [ToolKey] {
        model.settings.chatKeys.filter { $0 != .ctrl && $0 != .joystick && $0 != .keyboard }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let q = slashQuery, !matches.isEmpty {
                SlashPopup(query: q, matches: matches, pick: pick)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !chat.queue.isEmpty && !question {
                QueuedStack(chat: chat, agent: agentName)
                    .padding(.horizontal, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            VStack(spacing: 8) {
                if clipboardImage && chat.draftImages.count < 4 && !question {
                    HStack {
                        PasteButton(supportedContentTypes: [.image]) { providers in paste(providers) }
                            .labelStyle(.titleAndIcon)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .tint(Theme.selectedStrong)
                        Spacer()
                    }
                }
                if !chat.draftImages.isEmpty && !question {
                    drafts
                }
                if !(model.settings.hideBarWithKeyboard && HardwareKeyboard.shared.connected) {
                    keyStrip
                }
                inputRow
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .barChrome(model.settings.bottomBar, radius: 22, edge: .bottom)
        }
        .padding(.bottom, model.settings.bottomBar == .floating ? 4 : 0)
        .animation(.easeOut(duration: 0.15), value: matches.map(\.name))
        .animation(.easeOut(duration: 0.2), value: chat.queue.map(\.id))
        .photosPicker(isPresented: $showPicker, selection: $items, maxSelectionCount: 4, matching: .images)
        .sheet(isPresented: $editKeys) {
            NavigationStack {
                ToolbarSettingsView(initialTab: 1)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editKeys = false } } }
            }
            .preferredColorScheme(model.colorSchemeOverride)
        }
        .onChange(of: items) { _, new in
            guard !new.isEmpty else { return }
            Task { await load(new) }
        }
        .onChange(of: dict.text) { _, t in
            guard let base = dictBase else { return }
            text = base + (base.isEmpty || t.isEmpty ? "" : " ") + t
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            clipboardImage = UIPasteboard.general.hasImages
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            clipboardImage = UIPasteboard.general.hasImages
        }
        .onReceive(NotificationCenter.default.publisher(for: .herdrDictate)) { _ in toggleDictation() }
        .onReceive(NotificationCenter.default.publisher(for: .herdrInterrupt)) { _ in Task { await chat.interrupt() } }
    }

    private var drafts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chat.draftImages) { img in
                    Image(uiImage: img.thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { chat.draftImages.removeAll { $0.id == img.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .offset(x: 5, y: -5)
                        }
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
    }

    private var keyStrip: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stripKeys) { k in
                        PressKey(key: k, labels: model.settings.toolbarLabels, accent: k.answer && answering, glass: model.settings.toolbarGlass, disabled: chat.connection == nil) {
                            fire(k)
                        }
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            Button { editKeys = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit keys")
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button { showPicker = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 34, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(question)
            let slashOn = chat.draftCommand != nil || slashQuery != nil
            Button(action: startSlash) {
                Text("/")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(slashOn ? Theme.amber : Theme.text)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(slashOn ? Theme.amberBg : Theme.raised.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(slashOn ? Theme.amberBorder : Theme.border, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)
            .disabled(question)
            field
            micButton
            actionButton
        }
    }

    private var field: some View {
        HStack(alignment: .center, spacing: 6) {
            if let cmd = chat.draftCommand {
                Button { chat.draftCommand = nil } label: {
                    Text("/" + cmd)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.amberBg))
                }
                .buttonStyle(.plain)
            }
            PasteTextView(text: textBinding, placeholder: placeholder, font: .systemFont(ofSize: 15 * Typo.scale), focusToken: focus, dark: ThemeStore.shared.palette.dark, onFocus: { _ in
                clipboardImage = UIPasteboard.general.hasImages
            }, onImages: add, onDeleteEmpty: {
                if chat.draftCommand != nil { chat.draftCommand = nil }
            }, onSubmit: primary, onSubmitNow: sendNow)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(.system(size: 15 * Typo.scale)).foregroundStyle(Theme.dim).lineLimit(1).allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Theme.raised.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
    }

    private var micButton: some View {
        Button(action: toggleDictation) {
            Image(systemName: dict.listening ? "mic.fill" : "mic")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(dict.listening ? Theme.red : Theme.muted)
                .frame(width: 30, height: 38)
                .background {
                    if dict.listening {
                        Circle().fill(Theme.red.opacity(0.18)).scaleEffect(0.9 + CGFloat(dict.level) * 0.6)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dict.listening ? "Stop dictation" : "Dictate")
    }

    @ViewBuilder
    private var actionButton: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if chat.draftCommand != nil && !question {
            round("play.fill", fill: Theme.amber, ink: Theme.onAccent, busy: chat.sending, action: primary)
        } else if question {
            round("arrow.up", fill: trimmed.isEmpty ? Theme.raised : Theme.amber, ink: trimmed.isEmpty ? Theme.dim : Theme.onAccent, busy: false, action: primary)
                .disabled(trimmed.isEmpty)
        } else if !trimmed.isEmpty || !chat.draftImages.isEmpty {
            round(chat.agentBusy ? "text.append" : "arrow.up", fill: Theme.amber, ink: Theme.onAccent, busy: chat.sending, action: primary)
                .contextMenu {
                    Button { sendNow() } label: { Label("Send now", systemImage: "paperplane") }
                    Button { send() } label: { Label(chat.agentBusy ? "Queue until \(agentName) is done" : "Send", systemImage: "text.append") }
                }
                .accessibilityIdentifier(chat.agentBusy ? "queue-button" : "send-button")
        } else if chat.terminal?.agentState == .working {
            round("stop.fill", fill: Theme.text, ink: Theme.terminal, busy: false) { Task { await chat.interrupt() } }
        } else {
            round("arrow.up", fill: Theme.raised, ink: Theme.dim, busy: false) {}
                .disabled(true)
        }
    }

    private func round(_ symbol: String, fill: Color, ink: Color, busy: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Group {
                if busy { ProgressView().tint(ink) } else { Image(systemName: symbol).font(.system(size: 15, weight: .bold)) }
            }
            .foregroundStyle(ink)
            .frame(width: 38, height: 38)
            .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func fire(_ k: ToolKey) {
        switch k {
        case .paste:
            if let s = UIPasteboard.general.string { text += s }
        case .mic:
            toggleDictation()
        case .photo:
            showPicker = true
        case .commands:
            startSlash()
        case .terminal:
            if let tab = model.currentTab?.1 { model.setChat(false, tabID: tab.id) }
        default:
            if let n = k.coreName { Task { await chat.sendKey(n) } }
        }
    }

    private func startSlash() {
        if chat.draftCommand != nil {
            chat.draftCommand = nil
        } else if !chat.draft.hasPrefix("/") {
            chat.draft = "/" + chat.draft
        }
        focus += 1
    }

    private func pick(_ c: SlashCommand) {
        chat.draftCommand = c.name
        chat.draft = ""
        focus += 1
    }

    private func primary() {
        if question {
            if !chat.questionOther.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chat.questionSubmit += 1 }
            return
        }
        if let cmd = chat.draftCommand {
            let args = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                if await chat.runCommand(cmd, args: args) {
                    chat.draftCommand = nil
                    if chat.draft.trimmingCharacters(in: .whitespacesAndNewlines) == args { chat.draft = "" }
                }
            }
            return
        }
        if let q = slashQuery, let first = matches.first, !q.isEmpty, first.name.lowercased() != q.lowercased() {
            pick(first)
            return
        }
        send()
    }

    private func sendNow() {
        guard !question, chat.draftCommand == nil else { primary(); return }
        send(now: true)
    }

    private func send(now: Bool = false) {
        let t = chat.draft
        let imgs = chat.draftImages
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imgs.isEmpty else { return }
        if !now && (chat.agentBusy || !chat.queue.isEmpty) {
            chat.enqueue(text: t, images: imgs)
            chat.draft = ""
            chat.draftImages.removeAll()
            return
        }
        guard !chat.sending else { return }
        chat.draft = ""
        chat.draftImages.removeAll()
        Task {
            if await !chat.send(text: t, images: imgs.map { (name: $0.name, data: $0.data) }, thumbs: imgs.map(\.thumb)) {
                if chat.draft.isEmpty { chat.draft = t }
                if chat.draftImages.isEmpty { chat.draftImages = imgs }
            }
        }
    }

    private func toggleDictation() {
        if dict.listening {
            dict.stop { final in
                let base = dictBase ?? ""
                dictBase = nil
                if !final.isEmpty { text = base + (base.isEmpty ? "" : " ") + final }
                if model.settings.speechAutoSend && !final.isEmpty { primary() }
            }
        } else {
            dictBase = text
            Task {
                await dict.start(locale: model.settings.speechLocale, onDevice: model.settings.speechOnDevice)
                if case .failed(let m) = dict.state {
                    chat.notice = m
                    dictBase = nil
                }
            }
        }
    }

    private func newImage(_ ui: UIImage, data: Data?) {
        guard chat.draftImages.count < 4 else { return }
        let jpeg = ui.jpegData(compressionQuality: 0.85) ?? data ?? Data()
        guard !jpeg.isEmpty else { return }
        let name = "phone-\(Int(Date().timeIntervalSince1970))-\(chat.draftImages.count + 1).jpg"
        chat.draftImages.append(DraftImage(name: name, data: jpeg, thumb: ui.preparingThumbnail(of: CGSize(width: 300, height: 300 * ui.size.height / max(ui.size.width, 1))) ?? ui))
    }

    private func add(_ pasted: [UIImage]) {
        for ui in pasted { newImage(ui, data: nil) }
    }

    private func paste(_ providers: [NSItemProvider]) {
        for p in providers {
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let ui = UIImage(data: data) else { return }
                Task { @MainActor in newImage(ui, data: data) }
            }
        }
    }

    private func load(_ picked: [PhotosPickerItem]) async {
        for item in picked {
            guard let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) else { continue }
            newImage(ui, data: data)
        }
        items = []
    }
}
