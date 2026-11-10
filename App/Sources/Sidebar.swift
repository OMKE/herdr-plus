import SwiftUI
import HerdrKit

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var collapsed: Set<String> = []
    @State private var newTabSpace: Space?
    @State private var renaming: TabRef?
    @State private var closing: TabRef?
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if !model.needsYou.isEmpty {
                        sectionTitle("Needs you", count: model.needsYou.count, tint: Theme.amber)
                        ForEach(model.needsYou) { e in needsRow(e) }
                    }
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { waitingFirst.toggle() }
                        } label: {
                            Label(waitingFirst ? "Waiting first" : "Layout order", systemImage: waitingFirst ? "arrow.up.to.line" : "list.bullet")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(waitingFirst ? Theme.amber : Theme.dim)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    ForEach(groups, id: \.0) { group in
                        sectionTitle(group.0, count: nil, tint: Theme.muted)
                        ForEach(group.1) { s in spaceBlock(s) }
                    }
                    if !otherAgents.isEmpty {
                        sectionTitle("Other agents", count: nil, tint: Theme.muted)
                        ForEach(otherAgents) { e in agentRow(e) }
                    }
                }
                .padding(.bottom, 24)
            }
            footer
        }
        .background(Theme.chrome)
        .sheet(item: $newTabSpace) { s in NewTabSheet(space: s) }
        .sheet(item: $renaming) { r in RenameTabSheet(ref: r) }
        .confirmationDialog(closeTitle, isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }), titleVisibility: .visible) {
            Button("Close tab", role: .destructive) {
                guard let r = closing else { return }
                closing = nil
                Task {
                    do { try await model.closeTab(r) } catch { actionError = "Couldn't close the tab: " + AppModel.describe(error) }
                }
            }
            Button("Cancel", role: .cancel) { closing = nil }
        } message: {
            Text("Its terminals are stopped. This can't be undone.")
        }
        .alert("Tab", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var closeTitle: String {
        guard let r = closing, let (_, t) = model.tab(r) else { return "Close tab?" }
        return "Close \"\(t.name.isEmpty ? "Tab" : t.name)\"?"
    }

    private var groups: [(String, [Space])] {
        var order: [String] = []
        var map: [String: [Space]] = [:]
        for s in model.spaces {
            let k = model.machineLabel(s)
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(s)
        }
        return order.map { k in
            let list = map[k] ?? []
            guard waitingFirst else { return (k, list) }
            let waiting = list.filter(hasWaiting)
            return (k, waiting + list.filter { !hasWaiting($0) })
        }
    }

    @AppStorage("sidebar.waitingFirst") private var waitingFirst = true

    private func waiting(_ t: SpaceTab, in s: Space) -> Bool {
        let st = model.tabState(t, in: s)
        return st == .blocked
    }

    private func hasWaiting(_ s: Space) -> Bool { s.tabs.contains { waiting($0, in: s) } }

    private func orderedTabs(_ s: Space) -> [SpaceTab] {
        guard waitingFirst else { return s.tabs }
        return s.tabs.filter { waiting($0, in: s) } + s.tabs.filter { !waiting($0, in: s) }
    }

    private var otherAgents: [AgentEntry] { model.agents.filter { $0.space == nil } }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
            VStack(alignment: .leading, spacing: 1) {
                Text(model.settings.displayHost)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var statusColor: Color {
        switch model.phase {
        case .connected: Theme.green
        case .connecting, .reconnecting: Theme.amber
        default: Theme.red
        }
    }

    private var statusText: String {
        switch model.phase {
        case .connected: "Connected over Tailscale"
        case .connecting: "Connecting…"
        case .reconnecting: "Reconnecting…"
        case .failed: "Offline"
        case .onboarding: "Not set up"
        }
    }

    private func sectionTitle(_ t: String, count: Int?, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(t.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(tint)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.amberBg))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func needsRow(_ e: AgentEntry) -> some View {
        Button {
            if let s = e.space, let t = e.tab {
                model.select(TabRef(spaceUID: s.uid, tabID: t.id), pane: paneID(e), focusReply: true)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ProgramIcon(program: model.programs.program(for: e.terminal), size: 26)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(model.programs.displayName(for: e.terminal))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("· " + place(e))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    if let msg = e.terminal.status?.msg, !msg.isEmpty {
                        Text(msg)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                StateDot(state: e.terminal.agentState, size: 8).padding(.top, 6)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amberBg.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.amberBorder.opacity(0.8), lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private func place(_ e: AgentEntry) -> String {
        guard let s = e.space else { return e.terminal.machine ?? "" }
        if let t = e.tab, !t.name.isEmpty { return s.displayName + " / " + t.name }
        return s.displayName
    }

    private func paneID(_ e: AgentEntry) -> String? {
        guard let s = e.space, let t = e.tab else { return nil }
        return t.panes.first { p in
            if case .terminal(let l) = p.content { return LayoutDocument.address(l, machine: s.machine) == e.terminal.address }
            return false
        }?.id
    }

    private func spaceBlock(_ s: Space) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if collapsed.contains(s.uid) { collapsed.remove(s.uid) } else { collapsed.insert(s.uid) }
            } label: {
                HStack(spacing: 10) {
                    Monogram(space: s, size: 24)
                    Text(s.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    if let st = s.tabs.compactMap({ model.tabState($0, in: s) }).min(), st == .blocked || st == .error {
                        StateDot(state: st)
                    }
                    Image(systemName: collapsed.contains(s.uid) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                Button {
                    newTabSpace = s
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 34)
                .accessibilityLabel("New tab in \(s.displayName)")
                .accessibilityIdentifier("newtab-button")
            }
            if !collapsed.contains(s.uid) {
                ForEach(orderedTabs(s)) { t in tabRow(t, in: s) }
            }
        }
    }

    private func tabRow(_ t: SpaceTab, in s: Space) -> some View {
        let ref = TabRef(spaceUID: s.uid, tabID: t.id)
        let selected = model.selectedTab == ref
        let primary = model.primaryTerminal(t, in: s)
        let state = model.tabState(t, in: s)
        return Button {
            model.select(ref)
        } label: {
            HStack(spacing: 9) {
                ProgramIcon(program: primary.flatMap { model.programs.program(for: $0) }, size: 20)
                Text(t.name.isEmpty ? "Tab" : t.name)
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Theme.text : Theme.text.opacity(0.85))
                    .lineLimit(1)
                Spacer()
                if t.panes.count > 1 {
                    Text("\(t.panes.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                if let state { StateDot(state: state) }
            }
            .padding(.leading, 50)
            .padding(.trailing, 16)
            .padding(.vertical, 7)
            .background(selected ? Theme.selected : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { renaming = ref } label: { Label("Rename", systemImage: "pencil") }
            Button { newTabSpace = s } label: { Label("New tab", systemImage: "plus") }
            Divider()
            Button(role: .destructive) { closing = ref } label: { Label("Close tab", systemImage: "xmark") }
        }
    }

    private func agentRow(_ e: AgentEntry) -> some View {
        HStack(spacing: 9) {
            ProgramIcon(program: model.programs.program(for: e.terminal), size: 20)
            Text(model.programs.displayName(for: e.terminal))
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
            Text(e.terminal.machine ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
            Spacer()
            StateDot(state: e.terminal.agentState)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        Button {
            model.showSettings = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                Text("Settings")
                Spacer()
                if let v = model.coreInfo?.version, !v.isEmpty {
                    Text("core \(v)").font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
