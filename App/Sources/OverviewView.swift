import SwiftUI
import HerdrKit

struct ModeToggle: View {
    let chat: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            item("text.bubble", on: chat) { set(true) }
            item("terminal", on: !chat) { set(false) }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chromeDeep))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private func item(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Theme.text : Theme.dim)
                .frame(width: 32, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.selectedStrong : .clear))
        }
        .buttonStyle(.plain)
    }
}

struct Segmented<T: Hashable>: View {
    let items: [(T, String, Int?)]
    @Binding var selection: T
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { value, label, count in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.15)) { selection = value }
                } label: {
                    HStack(spacing: 5) {
                        Text(label).font(.system(size: compact ? 12 : 13, weight: .semibold))
                        if let count { Text("\(count)").font(.system(size: compact ? 11 : 12)).foregroundStyle(Theme.dim) }
                    }
                    .foregroundStyle(selection == value ? Theme.text : Theme.muted)
                    .frame(maxWidth: compact ? nil : .infinity)
                    .padding(.horizontal, compact ? 12 : 0)
                    .frame(height: compact ? 26 : 30)
                    .background(Capsule().fill(selection == value ? Theme.selectedStrong : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("seg-\(label.lowercased())")
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.chromeDeep))
    }
}

enum OverviewTab: Hashable { case agents, prs, todo }

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("overview.grouping") private var grouping = 0
    @AppStorage("overview.tab") private var tabRaw = 0
    @State private var tick = Date()

    private var data: OverviewData { model.overview }

    private var tab: Binding<OverviewTab> {
        Binding(get: { [.agents, .prs, .todo][min(max(tabRaw, 0), 2)] },
                set: { tabRaw = $0 == .agents ? 0 : $0 == .prs ? 1 : 2 })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Segmented(items: [(OverviewTab.agents, "Agents", model.agents.count),
                              (.prs, "PRs", data.repos.reduce(0) { $0 + $1.prs.count }),
                              (.todo, "Todo", data.todos.filter { !$0.done }.count)],
                      selection: tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            switch tab.wrappedValue {
            case .agents: AgentsPane(grouping: $grouping, close: { dismiss() })
            case .prs: PRsPane(close: { dismiss() })
            case .todo: TodoPane(close: { dismiss() })
            }
        }
        .background(Theme.terminal.ignoresSafeArea())
        .preferredColorScheme(model.colorSchemeOverride)
        .task {
            async let a: Void = data.refreshAgents(model)
            async let t: Void = data.loadTodos(model)
            _ = await (a, t)
            if data.prsUpdated == nil || Date().timeIntervalSince(data.prsUpdated!) > 120 { await data.refreshPRs(model) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Overview").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
            Spacer()
            Text(model.settings.displayHost).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            Circle().fill(model.connection == nil ? Theme.red : Theme.green).frame(width: 6, height: 6)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28).background(Circle().fill(Theme.raised))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("overview-close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

enum OverviewFormat {
    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return "\(n / 1000)k" }
        return "\(n)"
    }

    static func until(_ d: Date?) -> String? {
        guard let d else { return nil }
        let s = max(0, Int(d.timeIntervalSinceNow))
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return "\(h / 24)d" }
        return String(format: "%d:%02d", h, m)
    }

    static func ago(_ d: Date?) -> String {
        guard let d else { return "never" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 45 { return "just now" }
        if s < 3600 { return "\(max(1, s / 60))m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}

struct MeterBar: View {
    let label: String
    let percent: Double
    var suffix: String?
    var reset: String?
    var warn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(Theme.muted)
                Text("\(Int(percent.rounded()))%").foregroundStyle(warn ? Theme.amber : Theme.text)
                if let suffix { Text(suffix).foregroundStyle(Theme.dim) }
                if let reset {
                    Image(systemName: "arrow.clockwise").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
                    Text(reset).foregroundStyle(Theme.dim)
                }
            }
            .font(.system(size: 11))
            .lineLimit(1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.border)
                    Capsule().fill(warn ? Theme.amber : Theme.blue.opacity(0.85))
                        .frame(width: g.size.width * min(max(percent, 0), 100) / 100)
                }
            }
            .frame(height: 3)
        }
    }
}

struct StatePill: View {
    let state: AgentState

    var body: some View {
        HStack(spacing: 4) {
            if state == .working { ProgressView().controlSize(.mini).tint(Theme.stateColor(state)) }
            Text(Theme.stateLabel(state))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.stateColor(state))
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.stateColor(state).opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.stateColor(state).opacity(0.35)))
    }
}

private struct AgentsPane: View {
    @Environment(AppModel.self) private var model
    @Binding var grouping: Int
    let close: () -> Void

    private var data: OverviewData { model.overview }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stats
                HStack {
                    let machines = Set(model.agents.map { $0.terminal.machine ?? "" }).count
                    Text("\(model.agents.count) agents · \(machines) machine\(machines == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Segmented(items: [(0, "By status", nil), (1, "By space", nil)], selection: $grouping, compact: true)
                }
                if !data.accounts.isEmpty { accounts }
                if grouping == 0 {
                    ForEach(statusGroups, id: \.0) { state, entries in
                        section(Theme.stateLabel(state), entries: entries)
                    }
                } else {
                    ForEach(spaceGroups, id: \.0) { name, entries in
                        section(name, entries: entries)
                    }
                }
                if model.agents.isEmpty {
                    EmptyNote(title: "No agents running", detail: "Start one from the sidebar with +.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await data.refreshAgents(model) }
    }

    private var stats: some View {
        let a = model.agents
        let needs = model.needsYou.count
        let working = a.filter { $0.terminal.agentState == .working }.count
        let idle = a.filter { $0.terminal.agentState == .idle || $0.terminal.agentState == .unknown }.count
        let done = a.filter { $0.terminal.agentState == .done }.count
        return HStack(spacing: 6) {
            tile("Needs you", needs, Theme.amber, highlight: needs > 0)
            tile("Working", working, Theme.blue)
            tile("Idle", idle, Theme.text)
            tile("Done", done, Theme.green)
        }
    }

    private func tile(_ label: String, _ n: Int, _ tint: Color, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.system(size: 22, weight: .semibold)).foregroundStyle(n > 0 ? tint : Theme.dim)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(highlight ? Theme.amberBg : Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(highlight ? Theme.amberBorder : Theme.border))
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            ForEach(data.accounts) { a in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(a.account).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        Text("\(a.sessions) session\(a.sessions == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                    HStack(spacing: 14) {
                        if let f = a.fiveHour { MeterBar(label: "5h", percent: f.percent, reset: OverviewFormat.until(f.resetsAt), warn: f.percent >= 75) }
                        if let w = a.sevenDay { MeterBar(label: "7d", percent: w.percent, reset: OverviewFormat.until(w.resetsAt), warn: w.percent >= 75) }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            }
        }
    }

    private var statusGroups: [(AgentState, [AgentEntry])] {
        let groups = Dictionary(grouping: model.agents) { $0.terminal.agentState }
        return groups.keys.sorted().map { ($0, groups[$0]!) }
    }

    private var spaceGroups: [(String, [AgentEntry])] {
        var order: [String] = []
        var groups: [String: [AgentEntry]] = [:]
        for e in model.agents {
            let k = e.space?.displayName ?? "Other"
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(e)
        }
        return order.map { ($0, groups[$0]!.sorted { $0.terminal.agentState < $1.terminal.agentState }) }
    }

    private func section(_ title: String, entries: [AgentEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                Text("\(entries.count)").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            ForEach(entries) { e in AgentCard(entry: e, info: data.infos[e.terminal.address], close: close) }
        }
    }
}

private struct AgentCard: View {
    @Environment(AppModel.self) private var model
    let entry: AgentEntry
    let info: AgentInfo?
    let close: () -> Void

    var body: some View {
        let t = entry.terminal
        let program = model.programs.program(for: t)
        let needs = t.agentState == .blocked || t.agentState == .error
        Button {
            _ = model.select(address: t.address, focusReply: needs)
            close()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ProgramIcon(program: program, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text([program?.name ?? model.programs.displayName(for: t), entry.space?.displayName].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    StatePill(state: t.agentState)
                }
                meta
                bars
                if let last = t.status?.title, !last.isEmpty {
                    HStack {
                        Text(last).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                    }
                    .padding(.top, 8)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(needs ? Theme.amberBorder : Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("agent-card")
    }

    private var title: String {
        if let n = entry.tab?.name, !n.isEmpty { return n }
        return model.programs.displayName(for: entry.terminal)
    }

    @ViewBuilder private var meta: some View {
        let model = info?.usage?.model
        let branch = info?.repo?.branch
        let wt = info?.repo?.worktree
        if model != nil || branch != nil {
            HStack(spacing: 6) {
                if let model { Text(model).foregroundStyle(Theme.text) }
                if model != nil, branch != nil { Text("·").foregroundStyle(Theme.dim) }
                if let branch { Text(branch).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1) }
                if let wt {
                    HStack(spacing: 4) {
                        Text("worktree").foregroundStyle(Theme.blue)
                        Text(wt).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text).lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.blue.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.blue.opacity(0.35)))
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)
        }
    }

    @ViewBuilder private var bars: some View {
        if let u = info?.usage, u.contextPercent != nil || u.fiveHour != nil {
            HStack(spacing: 14) {
                if let c = u.contextPercent {
                    MeterBar(label: "Context", percent: c, suffix: u.contextSize.map { "of " + OverviewFormat.tokens($0) }, warn: c >= 75)
                }
                if let f = u.fiveHour {
                    MeterBar(label: "5h", percent: f.percent, reset: OverviewFormat.until(f.resetsAt), warn: f.percent >= 75)
                }
            }
        }
    }
}

struct EmptyNote: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Circle().stroke(Theme.dim, lineWidth: 1).frame(width: 26, height: 26)
                .overlay(Circle().stroke(Theme.border, lineWidth: 1).frame(width: 40, height: 40))
                .padding(.bottom, 10)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.horizontal, 24)
    }
}

private struct PRsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let close: () -> Void
    @State private var collapsed: Set<String> = []

    private var data: OverviewData { model.overview }

    var body: some View {
        let sessions = data.sessionBranches(model)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    if data.prsLoading { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.down").font(.system(size: 10)) }
                    Text(data.prsLoading ? "Checking pull requests…" : "Pull to refresh · updated \(OverviewFormat.ago(data.prsUpdated))")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity)
                ForEach(data.repos) { r in
                    repoSection(r, sessions: sessions)
                }
                if !data.prsLoading, data.prsUpdated != nil, data.repos.allSatisfy({ $0.prs.isEmpty && $0.error == nil }) {
                    let names = data.repos.map { $0.repo.name.split(separator: "/").last.map(String.init) ?? $0.repo.name }
                    EmptyNote(title: "No open PRs",
                              detail: names.isEmpty ? "None of your sessions are in a git repo with a GitHub remote." : "Nothing open in " + Self.list(names) + ".")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await data.refreshPRs(model) }
    }

    static func list(_ names: [String]) -> String {
        if names.count <= 1 { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " or " + names.last!
    }

    @ViewBuilder private func repoSection(_ r: RepoPRs, sessions: [String: AgentEntry]) -> some View {
        if !r.prs.isEmpty || r.error != nil {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if collapsed.contains(r.id) { collapsed.remove(r.id) } else { collapsed.insert(r.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: collapsed.contains(r.id) ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim).frame(width: 12)
                        Text(r.repo.name).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text)
                        Text("\(r.prs.count)").font(.system(size: 12)).foregroundStyle(Theme.dim)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                if !collapsed.contains(r.id) {
                    if let e = r.error {
                        Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(r.prs.enumerated()), id: \.element.id) { i, pr in
                                if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                                row(pr, session: sessions[pr.head])
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    }
                }
            }
        }
    }

    private func row(_ pr: PullRequest, session: AgentEntry?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(pr.author.prefix(1)).uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Self.avatar(pr.author)))
            VStack(alignment: .leading, spacing: 4) {
                (Text("#\(pr.number) ").foregroundStyle(Theme.dim) + Text(pr.title).foregroundStyle(Theme.text))
                    .font(.system(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(pr.head) → \(pr.base)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(ciColor(pr.ci)).frame(width: 6, height: 6)
                    Text(ciText(pr.ci)).foregroundStyle(Theme.text)
                    if let rv = reviewText(pr.review) { Text(rv.0).foregroundStyle(rv.1) }
                    Text("+\(pr.additions)").foregroundStyle(Theme.green)
                    Text("-\(pr.deletions)").foregroundStyle(Theme.red)
                }
                .font(.system(size: 12))
                .lineLimit(1)
                if pr.draft || session != nil {
                    HStack(spacing: 6) {
                        if pr.draft {
                            Text("Draft").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                .padding(.horizontal, 6).frame(height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border))
                        }
                        if let s = session { sessionChip(s) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { if let u = URL(string: pr.url) { openURL(u) } }
    }

    private func sessionChip(_ s: AgentEntry) -> some View {
        Button {
            _ = model.select(address: s.terminal.address, focusReply: false)
            close()
        } label: {
            HStack(spacing: 4) {
                ProgramIcon(program: model.programs.program(for: s.terminal), size: 12)
                Text("In session · " + (s.tab?.name.isEmpty == false ? s.tab!.name : model.programs.displayName(for: s.terminal)))
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.amberBg))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.amberBorder))
        }
        .buttonStyle(.plain)
    }

    static func avatar(_ name: String) -> Color {
        let palette = Theme.spacePalette
        let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return Color(hex: palette[h % palette.count])
    }

    private func ciColor(_ c: PullRequest.CI) -> Color {
        switch c {
        case .passing: Theme.green
        case .failing: Theme.red
        case .pending: Theme.amber
        case .none: Theme.dim
        }
    }

    private func ciText(_ c: PullRequest.CI) -> String {
        switch c {
        case .passing: "Checks passing"
        case .failing: "Checks failing"
        case .pending: "Checks running"
        case .none: "No checks"
        }
    }

    private func reviewText(_ r: PullRequest.Review) -> (String, Color)? {
        switch r {
        case .approved: ("Approved", Theme.green)
        case .changes: ("Changes requested", Theme.red)
        case .required: ("Review required", Theme.muted)
        case .none: nil
        }
    }
}

struct SessionOption: Identifiable, Hashable {
    var spaceUID: String
    var tabID: String
    var space: String
    var name: String
    var program: String?
    var state: AgentState?
    var id: String { spaceUID + "|" + tabID }
}

extension AppModel {
    var sessionOptions: [SessionOption] {
        spaces.flatMap { s in
            s.tabs.map { t in
                let term = primaryTerminal(t, in: s)
                let p = term.flatMap { programs.program(for: $0) }
                return SessionOption(spaceUID: s.uid, tabID: t.id, space: s.displayName,
                                     name: t.name.isEmpty ? (term.map { programs.displayName(for: $0) } ?? "Tab") : t.name,
                                     program: p?.key, state: tabState(t, in: s))
            }
        }
    }
}

private struct TodoPane: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void
    @State private var draft = ""
    @State private var showDone = false
    @State private var editing: TodoItem?
    @FocusState private var focused: Bool

    private var data: OverviewData { model.overview }

    var body: some View {
        let open = data.todos.filter { !$0.done }
        let done = data.todos.filter(\.done)
        let shown = (showDone ? done : open).sorted { $0.created > $1.created }
        List {
            Group {
                HStack(spacing: 8) {
                    TextField("Add a todo…", text: $draft)
                        .font(.system(size: 15))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(Capsule().fill(Theme.raised))
                        .overlay(Capsule().stroke(Theme.border))
                        .accessibilityIdentifier("todo-field")
                    Button(action: add) {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.muted : Theme.onAccent)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.raised : Theme.amber))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("todo-add")
                }
                HStack {
                    Segmented(items: [(false, "Open", open.count), (true, "Done", done.count)], selection: $showDone, compact: true)
                    Spacer()
                }
                if let e = data.todoError {
                    Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            ForEach(shown) { item in
                TodoRow(item: item, close: close,
                        toggle: { toggle(item) },
                        edit: { editing = item })
                    .listRowBackground(Theme.raised)
                    .listRowSeparatorTint(Theme.border)
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { remove(item) } label: { Text("Delete") }
                    }
                    .swipeActions(edge: .leading) {
                        Button { toggle(item) } label: { Text(item.done ? "Reopen" : "Done") }.tint(Theme.green)
                    }
            }
            if shown.isEmpty, data.todosLoaded {
                Text(showDone ? "Nothing done yet." : "No open todos. Add one above.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 30)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await data.loadTodos(model) }
        .sheet(item: $editing) { item in
            TodoEditSheet(item: item) { updated in
                data.editTodos(model) { list in list.map { $0.id == updated.id ? updated : $0 } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func add() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let item = TodoItem(text: t)
        data.editTodos(model) { [item] + $0.filter { $0.id != item.id } }
        showDone = false
    }

    private func toggle(_ item: TodoItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        data.editTodos(model) { list in list.map { var x = $0; if x.id == item.id { x.done.toggle() }; return x } }
    }

    private func remove(_ item: TodoItem) {
        data.editTodos(model) { $0.filter { $0.id != item.id } }
    }
}

private struct TodoRow: View {
    @Environment(AppModel.self) private var model
    let item: TodoItem
    let close: () -> Void
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) {
                ZStack {
                    Circle().stroke(item.done ? Theme.green : Theme.dim, lineWidth: 1.5).frame(width: 20, height: 20)
                    if item.done {
                        Circle().fill(Theme.green).frame(width: 20, height: 20)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.terminal)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("todo-check")
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? Theme.muted : Theme.text)
                    .strikethrough(item.done, color: Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: edit)
                if let chip { chip }
            }
        }
    }

    private var chip: AnyView? {
        guard let uid = item.spaceUID, let tabID = item.tabID else { return nil }
        let live = model.space(uid: uid)
        let tab = live?.tabs.first { $0.id == tabID }
        let spaceName = live?.displayName ?? (item.label?.components(separatedBy: " / ").first ?? "")
        let tabName = tab.map { $0.name.isEmpty ? "Tab" : $0.name } ?? (item.label?.components(separatedBy: " / ").last ?? "Closed")
        let program = item.program.flatMap { model.programs.programs[$0] }
        return AnyView(Button {
            guard tab != nil else { return }
            model.select(TabRef(spaceUID: uid, tabID: tabID))
            close()
        } label: {
            HStack(spacing: 5) {
                ProgramIcon(program: program, size: 12)
                Text(spaceName).foregroundStyle(Theme.muted)
                Text("/").foregroundStyle(Theme.dim)
                Text(tabName).foregroundStyle(tab == nil ? Theme.dim : Theme.text).strikethrough(tab == nil)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(Theme.chromeDeep))
            .overlay(Capsule().stroke(Theme.border))
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("todo-session-chip"))
    }
}

private struct TodoEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var item: TodoItem
    let save: (TodoItem) -> Void
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Todo", text: $item.text, axis: .vertical).lineLimit(1...6)
                    Toggle("Done", isOn: $item.done)
                }
                Section("Session") {
                    Button {
                        picking = true
                    } label: {
                        HStack {
                            if let p = item.program.flatMap({ model.programs.programs[$0] }) { ProgramIcon(program: p, size: 18) }
                            Text(item.label ?? "Attach session").foregroundStyle(item.label == nil ? Theme.amber : Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                        }
                    }
                    .accessibilityIdentifier("todo-attach")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.terminal)
            .navigationTitle("Edit todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.muted) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !item.text.isEmpty { save(item) }
                        dismiss()
                    }
                    .foregroundStyle(Theme.amber)
                }
            }
            .sheet(isPresented: $picking) {
                AttachSessionSheet(selected: item.tabID.map { (item.spaceUID ?? "") + "|" + $0 }) { opt in
                    item.spaceUID = opt?.spaceUID
                    item.tabID = opt?.tabID
                    item.label = opt.map { $0.space + " / " + $0.name }
                    item.program = opt?.program
                }
                .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(model.colorSchemeOverride)
    }
}

struct AttachSessionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var selected: String?
    let done: (SessionOption?) -> Void
    @State private var query = ""

    var body: some View {
        let all = model.sessionOptions
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) || $0.space.lowercased().contains(q) }
        var order: [String] = []
        var groups: [String: [SessionOption]] = [:]
        for o in filtered {
            if groups[o.space] == nil { order.append(o.space) }
            groups[o.space, default: []].append(o)
        }
        return NavigationStack {
            List {
                Button { selected = nil } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 5).stroke(Theme.dim, style: StrokeStyle(lineWidth: 1, dash: [3])).frame(width: 18, height: 18)
                        Text("No session").foregroundStyle(Theme.text)
                        Spacer()
                        if selected == nil { Image(systemName: "checkmark").foregroundStyle(Theme.amber) }
                    }
                }
                ForEach(order, id: \.self) { space in
                    Section(space) {
                        ForEach(groups[space]!) { o in
                            Button { selected = o.id } label: {
                                HStack(spacing: 10) {
                                    ProgramIcon(program: o.program.flatMap { model.programs.programs[$0] }, size: 18)
                                    Text(o.name).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer()
                                    if let s = o.state { Text(Theme.stateLabel(s)).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                                    if selected == o.id { Image(systemName: "checkmark").foregroundStyle(Theme.amber) }
                                }
                            }
                            .accessibilityIdentifier("attach-option")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sessions")
            .scrollContentBackground(.hidden)
            .background(Theme.terminal)
            .navigationTitle("Attach session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.muted) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        done(all.first { $0.id == selected })
                        dismiss()
                    }
                    .foregroundStyle(Theme.amber)
                    .accessibilityIdentifier("attach-done")
                }
            }
        }
        .preferredColorScheme(model.colorSchemeOverride)
    }
}
