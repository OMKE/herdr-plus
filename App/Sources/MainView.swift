import SwiftUI
import HerdrKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .onboarding:
                OnboardingView()
            case .failed(let msg) where model.spaces.isEmpty:
                CantReachView(message: msg)
            case .connecting where model.spaces.isEmpty:
                ConnectingView()
            case .reconnecting where model.spaces.isEmpty:
                ConnectingView()
            default:
                MainView()
                    .background(ShortcutLayer())
            }
        }
        .background(Theme.terminal.ignoresSafeArea())
        .preferredColorScheme(model.colorSchemeOverride)
        .tint(Theme.amber)
        .background(SchemeProbe())
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-preview-settings") { model.showSettings = true }
        }
        .overlay {
            if ProcessInfo.processInfo.arguments.contains("-preview-keybar") {
                VStack {
                    Spacer()
                    KeyBar(blocked: false, session: nil, keys: ToolKey.terminalChoices)
                        .padding(.top, 6)
                        .barChrome(.floating, radius: 18, edge: .bottom)
                        .accessibilityIdentifier("preview-keybar")
                }
                .background(Theme.terminal)
            }
            if ProcessInfo.processInfo.arguments.contains("-preview-working") {
                WorkingPreview()
            }
        }
        #endif
        .sheet(isPresented: $model.showOverview) {
            OverviewView()
        }
        .sheet(item: $model.workspace) { t in
            WorkspaceSheet(target: t)
        }
    }
}

struct SchemeProbe: UIViewRepresentable {
    @Environment(AppModel.self) private var model

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.onChange = { [weak model] dark in model?.setSystemDark(dark) }
        return v
    }

    func updateUIView(_ v: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        var onChange: ((Bool) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (v: ProbeView, _) in v.report() }
        }

        func report() {
            guard let screen = window?.windowScene?.screen else { return }
            let dark = screen.traitCollection.userInterfaceStyle == .dark
            DispatchQueue.main.async { self.onChange?(dark) }
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 300)
                Rectangle().fill(Theme.border).frame(width: 1).ignoresSafeArea()
                TabScreen(isPad: true)
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    TabScreen(isPad: false)
                    if model.drawerOpen {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { model.drawerOpen = false } }
                            .transition(.opacity)
                        SidebarView()
                            .frame(width: min(360, geo.size.width * 0.86))
                            .transition(.move(edge: .leading))
                    }
                }
            }
            .background(EdgeSwipe(enabled: !model.drawerOpen, onClose: {
                withAnimation(.easeOut(duration: 0.2)) { model.drawerOpen = false }
            }) {
                withAnimation(.easeOut(duration: 0.22)) { model.drawerOpen = true }
            })
            .onChange(of: model.drawerOpen) { _, open in
                guard open else { return }
                model.pool.dismissKeyboards()
            }
        }
    }
}

struct EdgeSwipe: UIViewRepresentable {
    var enabled: Bool
    var onClose: () -> Void = {}
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Host {
        let v = Host()
        v.isUserInteractionEnabled = false
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ v: Host, context: Context) {
        context.coordinator.action = action
        context.coordinator.close = onClose
        context.coordinator.recognizer.isEnabled = enabled
        context.coordinator.closer.isEnabled = !enabled
    }

    static func dismantleUIView(_ v: Host, coordinator: Coordinator) {
        coordinator.recognizer.view?.removeGestureRecognizer(coordinator.recognizer)
        coordinator.closer.view?.removeGestureRecognizer(coordinator.closer)
    }

    final class Host: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let c = coordinator, c.recognizer.view !== window else { return }
            c.recognizer.view?.removeGestureRecognizer(c.recognizer)
            c.closer.view?.removeGestureRecognizer(c.closer)
            window.addGestureRecognizer(c.recognizer)
            window.addGestureRecognizer(c.closer)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void = {}
        lazy var recognizer: UIScreenEdgePanGestureRecognizer = {
            let r = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(pan(_:)))
            r.edges = .left
            r.delegate = self
            return r
        }()
        var close: () -> Void = {}
        lazy var closer: UIPanGestureRecognizer = {
            let r = UIPanGestureRecognizer(target: self, action: #selector(closePan(_:)))
            r.delegate = self
            r.cancelsTouchesInView = false
            return r
        }()
        private var fired = false

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === closer, let v = g.view, let p = g as? UIPanGestureRecognizer else { return true }
            let vel = p.velocity(in: v)
            return vel.x < 0 && abs(vel.x) > abs(vel.y)
        }

        @objc func closePan(_ r: UIPanGestureRecognizer) {
            switch r.state {
            case .began:
                fired = false
            case .changed:
                guard !fired, let v = r.view else { return }
                let t = r.translation(in: v)
                if t.x < -50, abs(t.y) < -t.x {
                    fired = true
                    close()
                }
            default:
                fired = false
            }
        }

        @objc func pan(_ r: UIScreenEdgePanGestureRecognizer) {
            switch r.state {
            case .began:
                fired = false
            case .changed:
                guard !fired, let v = r.view else { return }
                let t = r.translation(in: v)
                if t.x > 40, abs(t.y) < t.x {
                    fired = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                }
            default:
                fired = false
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

struct TabScreen: View {
    let isPad: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if !chatShown { header }
            banner
            if let (space, tab) = model.currentTab {
                content(space: space, tab: tab)
            } else {
                emptyState
            }
        }
        .background(Theme.terminal)
    }

    private var chatShown: Bool {
        guard let (space, tab) = model.currentTab else { return false }
        return chatAddress(space: space, tab: tab) != nil && model.showsChat(tabID: tab.id)
    }

    @ViewBuilder
    private var banner: some View {
        if case .reconnecting(let msg) = model.phase {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.amber)
                Text("Reconnecting to \(model.settings.displayHost)…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amber)
                if !msg.isEmpty {
                    Text(msg).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.amberBg)
        } else if case .failed(let msg) = model.phase {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text(msg).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(2)
                Spacer()
                Button("Retry") { model.connect() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.amberBg)
        }
    }

    private var header: some View {
        let current = model.currentTab
        let primary = current.flatMap { model.primaryTerminal($0.1, in: $0.0) }
        let state = current.flatMap { model.tabState($0.1, in: $0.0) }
        return HStack(spacing: 10) {
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
            if let (space, tab) = current {
                ProgramIcon(program: primary.flatMap { model.programs.program(for: $0) }, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    BarTitle(title: tab.name.isEmpty ? (primary.map { model.programs.displayName(for: $0) } ?? "Tab") : tab.name, blocked: state == .blocked) {
                        if let state, state != .unknown, state != .idle {
                            StateDot(state: state)
                        }
                    }
                    Text("\(space.displayName) · \(model.machineLabel(space))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Text("Herdr").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
            }
            Spacer(minLength: 4)
            if let (space, tab) = current {
                WorkspaceMenuButton(terminal: model.primaryTerminal(tab, in: space), fallbackFolder: space.folder, machine: space.machine)
            }
            Button {
                model.showOverview = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, height: 34)
            }
            .buttonStyle(.plain)
            if let (space, tab) = current, chatAddress(space: space, tab: tab) != nil {
                ChatModeSwitch(chat: false) { model.setChat($0, tabID: tab.id) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .barChrome(model.settings.topBar, radius: 20, edge: .top)
        .padding(.top, model.settings.topBar == .floating ? 4 : 0)
        .padding(.bottom, model.settings.topBar == .floating ? 4 : 0)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "rectangle.stack").font(.system(size: 34)).foregroundStyle(Theme.dim)
            Text(model.spaces.isEmpty ? "No spaces yet" : "Pick a tab")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
            if !isPad {
                Button("Open spaces") { withAnimation { model.drawerOpen = true } }
                    .foregroundStyle(Theme.amber)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func focusedPane(_ tab: SpaceTab) -> LayoutNode? {
        let panes = tab.panes
        if let id = model.selectedPane[tab.id], let p = panes.first(where: { $0.id == id }) { return p }
        return panes.first { if case .terminal = $0.content { true } else { false } } ?? panes.first
    }

    private func address(_ pane: LayoutNode?, space: Space) -> String? {
        guard let pane, case .terminal(let l) = pane.content else { return nil }
        return LayoutDocument.address(l, machine: space.machine)
    }

    private func chatAddress(space: Space, tab: SpaceTab) -> String? {
        guard let addr = address(focusedPane(tab), space: space), let t = model.store[addr], t.isLive, Locator.agentKind(t) != nil else { return nil }
        return addr
    }

    @ViewBuilder
    private func content(space: Space, tab: SpaceTab) -> some View {
        if let addr = chatAddress(space: space, tab: tab), model.showsChat(tabID: tab.id) {
            ChatView(chat: model.chat(for: addr), space: space, tab: tab, isPad: isPad, selectedPane: focusedPane(tab)?.id)
                .id(addr)
        } else {
            terminalContent(space: space, tab: tab)
        }
    }

    @ViewBuilder
    private func terminalContent(space: Space, tab: SpaceTab) -> some View {
        let focus = focusedPane(tab)
        let addr = address(focus, space: space)
        let term = addr.flatMap { model.store[$0] }
        let session = addr.map { model.pool.session(for: $0, fontSize: CGFloat(model.settings.fontSize)) }
        VStack(spacing: 0) {
            if isPad {
                SplitView(node: tab.root, space: space, tab: tab, focusedID: focus?.id)
                    .padding(4)
            } else {
                if tab.panes.count > 1 {
                    PaneSwitcher(space: space, tab: tab, selected: focus?.id)
                }
                if let focus {
                    PaneView(pane: focus, space: space, tab: tab, focused: true)
                        .id(focus.id)
                }
            }
            if addr != nil, !(model.settings.hideBarWithKeyboard && HardwareKeyboard.shared.connected) {
                KeyBar(blocked: term?.agentState == .blocked, session: session, keys: model.settings.termKeys, labels: model.settings.toolbarLabels, glass: model.settings.toolbarGlass)
                    .padding(.top, 6)
                    .barChrome(model.settings.bottomBar, radius: 18, edge: .bottom)
                    .padding(.top, model.settings.bottomBar == .floating ? 6 : 0)
                    .padding(.bottom, model.settings.bottomBar == .floating ? 4 : 0)
            }
        }
        .onChange(of: model.focusReplyToken) { _, _ in session?.rawKeyboard = true }
    }
}

struct PaneSwitcher: View {
    let space: Space
    let tab: SpaceTab
    let selected: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tab.panes) { p in
                    let isSel = p.id == selected
                    Button {
                        model.selectedPane[tab.id] = p.id
                    } label: {
                        HStack(spacing: 6) {
                            paneIcon(p)
                            Text(label(p)).font(.system(size: 13, weight: isSel ? .semibold : .regular)).lineLimit(1)
                            if let st = state(p), st != .unknown, st != .idle { StateDot(state: st, size: 6) }
                        }
                        .foregroundStyle(isSel ? Theme.text : Theme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isSel ? Theme.selectedStrong : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.chromeDeep))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Theme.chrome)
    }

    private func term(_ p: LayoutNode) -> Terminal? {
        if case .terminal(let l) = p.content { return model.terminal(l, in: space) }
        return nil
    }

    private func state(_ p: LayoutNode) -> AgentState? { term(p).flatMap { $0.isAgent ? $0.agentState : nil } }

    @ViewBuilder
    private func paneIcon(_ p: LayoutNode) -> some View {
        if let t = term(p) {
            ProgramIcon(program: model.programs.program(for: t), size: 16)
        } else {
            Image(systemName: "puzzlepiece.extension").font(.system(size: 11))
        }
    }

    private func label(_ p: LayoutNode) -> String {
        switch p.content {
        case .terminal:
            if let t = term(p) { return model.programs.displayName(for: t) }
            return "Terminal"
        case .mod(let name, _):
            return name
        case .agent:
            return "Agent"
        case .reference:
            return "Linked pane"
        case .empty:
            return "Empty"
        }
    }
}

struct SplitView: View {
    let node: LayoutNode
    let space: Space
    let tab: SpaceTab
    let focusedID: String?

    var body: some View {
        switch node.kind {
        case .block:
            PaneView(pane: node, space: space, tab: tab, focused: node.id == focusedID)
        case .stack:
            let idx = min(max(node.active ?? 0, 0), max(node.children.count - 1, 0))
            if node.children.indices.contains(idx) {
                SplitView(node: node.children[idx], space: space, tab: tab, focusedID: focusedID)
            }
        case .row, .column:
            GeometryReader { geo in
                let horizontal = node.kind == .row
                let total = horizontal ? geo.size.width : geo.size.height
                let sizes = Self.sizes(node.children, total: total - CGFloat(max(node.children.count - 1, 0)) * 4)
                let layout = horizontal ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 4))
                layout {
                    ForEach(Array(node.children.enumerated()), id: \.element.id) { i, child in
                        SplitView(node: child, space: space, tab: tab, focusedID: focusedID)
                            .frame(width: horizontal ? sizes[i] : nil, height: horizontal ? nil : sizes[i])
                    }
                }
            }
        }
    }

    static func sizes(_ children: [LayoutNode], total: CGFloat) -> [CGFloat] {
        let fixed = children.reduce(0.0) { $0 + ($1.px ?? 0) }
        let weights = children.map { $0.px == nil ? ($0.weight ?? 1) : 0 }
        let wsum = max(weights.reduce(0, +), 0.0001)
        let rest = max(total - fixed, 0)
        return children.enumerated().map { i, c in
            if let px = c.px { return min(px, total) }
            return rest * weights[i] / wsum
        }
    }
}

struct PaneView: View {
    let pane: LayoutNode
    let space: Space
    let tab: SpaceTab
    let focused: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            switch pane.content {
            case .terminal(let local):
                TerminalHost(address: LayoutDocument.address(local, machine: space.machine))
            case .mod(let name, _):
                UnsupportedPanel(title: name, kind: "mod", space: space, tab: tab)
            case .agent:
                UnsupportedPanel(title: "Agent view", kind: "panel", space: space, tab: tab)
            case .reference:
                UnsupportedPanel(title: "Linked pane", kind: "panel", space: space, tab: tab)
            case .empty:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.terminal)
        .overlay {
            if sizeClass == .regular {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focused ? Theme.amber.opacity(0.55) : Theme.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: sizeClass == .regular ? 6 : 0))
        .simultaneousGesture(TapGesture().onEnded {
            if !focused { model.selectedPane[tab.id] = pane.id }
        })
    }
}

struct TerminalHost: View {
    let address: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let session = model.pool.session(for: address, fontSize: CGFloat(model.settings.fontSize))
        ZStack {
            TerminalPaneView(session: session)
            switch session.status {
            case .attaching:
                ProgressView().tint(Theme.muted)
            case .closed(let reason):
                overlayCard(icon: "stop.circle", text: reason == "killed" ? "Terminal closed" : "Terminal \(reason)")
            case .failed(let msg):
                overlayCard(icon: "exclamationmark.triangle", text: msg)
            default:
                EmptyView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let m = session.mirrorSize {
                Button {
                    session.takeOver()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                        Text("Mac size \(m.cols)×\(m.rows) · Fit to phone")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.amberBg))
                    .overlay(Capsule().stroke(Theme.amberBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onAppear {
            session.appeared()
            session.ensureAttached(connection: model.connection, generation: model.connectionGeneration)
        }
        .onDisappear { session.disappeared() }
        .onChange(of: model.connectionGeneration) { _, g in session.ensureAttached(connection: model.connection, generation: g) }
    }

    private func overlayCard(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).lineLimit(2)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.muted)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
    }
}

struct UnsupportedPanel: View {
    let title: String
    let kind: String
    let space: Space
    let tab: SpaceTab
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 30))
                .foregroundStyle(Theme.dim)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("This \(kind) can't be shown on iOS yet. It keeps working on your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            if let agentPane {
                Button {
                    model.selectedPane[tab.id] = agentPane.0.id
                } label: {
                    Text("Show \(agentPane.1)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.amber))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var agentPane: (LayoutNode, String)? {
        for p in tab.panes {
            if case .terminal(let l) = p.content, let t = model.terminal(l, in: space) {
                return (p, model.programs.displayName(for: t))
            }
        }
        return nil
    }
}

struct ConnectingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.amber).controlSize(.large)
            Text("Connecting to \(model.settings.displayHost)…")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
            if case .reconnecting(let msg) = model.phase, !msg.isEmpty {
                Text(msg).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(.horizontal, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.terminal)
    }
}

struct CantReachView: View {
    let message: String
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Theme.amber)
            Text("Can't reach \(model.settings.displayHost)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Check that Tailscale is connected on this phone and that your Mac is awake.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button {
                    model.connect()
                } label: {
                    Text("Retry")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 130, height: 44)
                        .background(Capsule().fill(Theme.amber))
                }
                Button {
                    if let u = URL(string: "tailscale://") { openURL(u) }
                } label: {
                    Text("Open Tailscale")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 150, height: 44)
                        .background(Capsule().fill(Theme.raised))
                        .overlay(Capsule().stroke(Theme.border))
                }
            }
            .padding(.top, 8)
            Spacer()
            Button("Settings") { model.showSettings = true }
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.terminal)
    }
}
