import Foundation
import SwiftUI
import Observation
import Network
import UserNotifications
import HerdrKit
import HerdrSSH

struct TabRef: Hashable {
    var spaceUID: String
    var tabID: String
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case onboarding
        case connecting
        case connected
        case reconnecting(String)
        case failed(String)
    }

    var settings: AppSettings {
        didSet {
            settings.save()
            restyle()
        }
    }

    var colorSchemeOverride: ColorScheme? {
        switch settings.appearance {
        case .system: ThemeStore.shared.systemDark ? .dark : .light
        case .light: .light
        case .dark: .dark
        }
    }

    func setSystemDark(_ dark: Bool) {
        guard ThemeStore.shared.systemDark != dark else { return }
        ThemeStore.shared.systemDark = dark
        restyle()
    }

    private func restyle() {
        let t = ThemeStore.shared
        let before = (t.palette, t.terminalFont)
        let meta = t.optionAsMeta
        t.apply(settings)
        if meta != t.optionAsMeta { pool.setOptionAsMeta(t.optionAsMeta) }
        if before.0 != t.palette { pool.apply(palette: t.palette) }
        if before.1 != t.terminalFont { pool.setFont(size: CGFloat(settings.fontSize)) }
    }
    var phase: Phase
    var store = TerminalStore()
    var spaces: [Space] = []
    var machines: [Machine] = []
    var coreInfo: CoreInfo?
    var latencyMs: Int?
    var connection: CoreConnection?
    var connectionGeneration = 0
    var selectedTab: TabRef?
    var selectedPane: [String: String] = [:]
    var drawerOpen = false
    var focusReplyToken = 0
    var pendingDeepLink: String?
    var showSettings = false
    let programs = Programs.bundled
    @ObservationIgnored let pool = SessionPool()
    @ObservationIgnored let chats = ChatPool()
    var showOverview = false
    var workspace: WorkspaceTarget?
    @ObservationIgnored let overview = OverviewData()
    var terminalTabs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "terminalTabs") ?? []) {
        didSet { UserDefaults.standard.set(Array(terminalTabs), forKey: "terminalTabs") }
    }

    func chat(for address: String) -> ChatController { chats.chat(for: address, app: self) }

    func showsChat(tabID: String) -> Bool { !terminalTabs.contains(tabID) }

    func setChat(_ on: Bool, tabID: String) {
        if on { terminalTabs.remove(tabID) } else { terminalTabs.insert(tabID) }
    }

    private var connectTask: Task<Void, Never>?
    private var layoutTask: Task<Void, Never>?
    @ObservationIgnored private var lastSignal = Date()
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var bgTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var pathSatisfied = true
    @ObservationIgnored private var pathInterfaces: [NWInterface.InterfaceType] = []
    @ObservationIgnored private var lastBadge = -1

    init() {
        let s = AppSettings.load()
        settings = s
        ThemeStore.shared.apply(s)
        phase = s.isComplete ? .connecting : .onboarding
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            let kinds = [NWInterface.InterfaceType.wifi, .cellular, .wiredEthernet, .other].filter { path.usesInterfaceType($0) }
            Task { @MainActor in self?.pathChanged(ok, kinds) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "herdr.path"))
    }

    private func pathChanged(_ ok: Bool, _ kinds: [NWInterface.InterfaceType]) {
        let wasOK = pathSatisfied
        let changed = kinds != pathInterfaces
        pathSatisfied = ok
        pathInterfaces = kinds
        guard ok, settings.isComplete, backgroundedAt == nil else { return }
        if connection == nil {
            if !wasOK || changed { connect() }
        } else if !wasOK || changed {
            checkHealth()
        }
    }

    func enteredBackground() {
        backgroundedAt = Date()
        BackgroundRefresh.schedule()
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "herdr.finish") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    private func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    func checkHealth() {
        guard let c = connection, !checking else { return }
        checking = true
        Task { [weak self] in
            do {
                _ = try await c.call("machine.list", [:], timeout: .seconds(3))
                self?.lastSignal = Date()
            } catch {
                if let self, self.connection === c { await c.close() }
            }
            self?.checking = false
        }
    }

    func measureLatency() async {
        guard let c = connection else { latencyMs = nil; return }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await c.call("machine.list", [:], timeout: .seconds(5))
            let d = clock.now - start
            latencyMs = Int(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        } catch {
            latencyMs = nil
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.backgroundedAt == nil else { continue }
                if self.connection != nil, Date().timeIntervalSince(self.lastSignal) > 40 { self.checkHealth() }
            }
        }
    }

    func updateBadge() {
        let n = needsYou.count
        guard n != lastBadge else { return }
        lastBadge = n
        UNUserNotificationCenter.current().setBadgeCount(n)
    }

    func requestBadgePermission() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { _, _ in }
        }
    }

    var terminals: [Terminal] { store.all }

    var agents: [AgentEntry] { AgentOrdering.entries(spaces: spaces, terminals: store.all) }

    var needsYou: [AgentEntry] { AgentOrdering.needsYou(agents) }

    func space(uid: String) -> Space? { spaces.first { $0.uid == uid } }

    func tab(_ ref: TabRef) -> (Space, SpaceTab)? {
        guard let s = space(uid: ref.spaceUID), let t = s.tabs.first(where: { $0.id == ref.tabID }) else { return nil }
        return (s, t)
    }

    var currentTab: (Space, SpaceTab)? { selectedTab.flatMap(tab) }

    func terminal(_ local: String, in space: Space) -> Terminal? {
        store[LayoutDocument.address(local, machine: space.machine)]
    }

    func tabState(_ tab: SpaceTab, in space: Space) -> AgentState? {
        tab.terminals.compactMap { terminal($0, in: space) }.filter(\.isAgent).map(\.agentState).min()
    }

    func primaryTerminal(_ tab: SpaceTab, in space: Space) -> Terminal? {
        let ts = tab.terminals.compactMap { terminal($0, in: space) }
        return ts.filter(\.isAgent).min { $0.agentState < $1.agentState } ?? ts.first
    }

    func machineLabel(_ space: Space) -> String {
        space.machine ?? settings.displayHost
    }

    func select(_ ref: TabRef, pane: String? = nil, focusReply: Bool = false) {
        selectedTab = ref
        if let pane { selectedPane[ref.tabID] = pane }
        drawerOpen = false
        if focusReply { focusReplyToken += 1 }
    }

    func select(address: String, focusReply: Bool) -> Bool {
        for s in spaces {
            for t in s.tabs {
                for p in t.panes {
                    if case .terminal(let local) = p.content, LayoutDocument.address(local, machine: s.machine) == address {
                        select(TabRef(spaceUID: s.uid, tabID: t.id), pane: p.id, focusReply: focusReply)
                        return true
                    }
                }
            }
        }
        return false
    }

    func handle(url: URL) {
        guard url.scheme == "herdr-ios" else { return }
        if url.host == "terminal" {
            let raw = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
            let address = raw.removingPercentEncoding ?? raw
            if !select(address: address, focusReply: true) { pendingDeepLink = address }
        }
        if connection == nil, settings.isComplete { connect() }
    }

    private func ensureSelection() {
        if let pending = pendingDeepLink, select(address: pending, focusReply: true) {
            pendingDeepLink = nil
            return
        }
        if let sel = selectedTab, tab(sel) != nil { return }
        if let first = needsYou.first, let s = first.space, let t = first.tab {
            selectedTab = TabRef(spaceUID: s.uid, tabID: t.id)
            return
        }
        if let s = spaces.first, let t = s.tabs.first {
            selectedTab = TabRef(spaceUID: s.uid, tabID: t.id)
        }
    }

    func finishOnboarding(_ s: AppSettings) {
        var s = s
        s.onboarded = true
        settings = s
        connect()
    }

    func resetOnboarding() {
        disconnect()
        settings.onboarded = false
        phase = .onboarding
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        let c = connection
        connection = nil
        Task { await c?.close() }
    }

    func becameActive() {
        endBackgroundTask()
        let away = backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0
        backgroundedAt = nil
        guard settings.isComplete else { phase = .onboarding; return }
        if connection == nil {
            if connectTask != nil, away < 1, !isFailed { return }
            connect()
        } else if away > 3 {
            checkHealth()
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    func connect() {
        guard settings.isComplete else { phase = .onboarding; return }
        connectTask?.cancel()
        connectTask = Task { [weak self] in await self?.connectLoop() }
        startWatchdog()
    }

    private func connectLoop() async {
        var attempt = 0
        var lastError = ""
        while !Task.isCancelled {
            if connection == nil {
                phase = (attempt == 0 && spaces.isEmpty) ? .connecting : .reconnecting(lastError)
            }
            do {
                let key = try KeyStore.loadOrCreate()
                let transport = try await SSHTransport.connect(settings.target, fingerprint: settings.fingerprint, key: key)
                let conn = CoreConnection(transport: transport)
                let info = try await conn.start()
                let sub = try await conn.subscribeEvents()
                if Task.isCancelled { await conn.close(); return }
                coreInfo = info
                store.reset(seq: sub.seq, terminals: sub.terminals)
                connection = conn
                lastSignal = Date()
                connectionGeneration += 1
                await refreshLayouts()
                phase = .connected
                attempt = 0
                requestBadgePermission()
                updateBadge()
                for await n in sub.stream {
                    lastSignal = Date()
                    apply(n)
                }
                if Task.isCancelled { return }
                connection = nil
                lastError = "Connection lost"
                await conn.close()
            } catch {
                if Task.isCancelled { return }
                lastError = Self.describe(error)
                if case SSHTransportError.hostKeyMismatch = error {
                    phase = .failed(lastError)
                    connectTask = nil
                    return
                }
            }
            attempt += 1
            if spaces.isEmpty && attempt >= 3 {
                phase = .failed(lastError)
                connectTask = nil
                return
            }
            phase = .reconnecting(lastError)
            let delay = attempt == 1 ? 0.4 : min(pow(2.0, Double(min(attempt - 1, 4))), 15)
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled, !pathSatisfied || backgroundedAt != nil {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? SSHTransportError { return e.description }
        if let e = error as? CoreError { return e.description }
        if let e = error as? RPCError { return e.message }
        let s = String(describing: error)
        if s.contains("authentication") || s.contains("allAuthenticationOptionsFailed") { return "SSH key was not accepted. Add the app's public key to ~/.ssh/authorized_keys on your Mac." }
        if s.contains("connectTimeout") || s.contains("timeout") { return "Timed out. Is Tailscale on?" }
        if s.contains("connectionRefused") || s.contains("refused") { return "Connection refused. Is Remote Login on?" }
        return s
    }

    private func apply(_ n: CoreNotification) {
        switch n {
        case .event(let e):
            if e.type == "doc" {
                scheduleLayoutRefresh()
            } else {
                store.apply(e)
                updateBadge()
            }
        case .missed(let seq, let ts):
            store.reset(seq: seq, terminals: ts)
            updateBadge()
            scheduleLayoutRefresh()
        case .heartbeat:
            break
        }
    }

    private func scheduleLayoutRefresh() {
        layoutTask?.cancel()
        layoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await self?.refreshLayouts()
        }
    }

    func refreshLayouts() async {
        guard let c = connection else { return }
        var all: [Space] = []
        if let local = try? await c.layout() { all += local.spaces }
        let ms = (try? await c.machines()) ?? []
        machines = ms
        for m in ms where m.isConnected && !m.temporary {
            if let d = try? await c.layout(on: m.name) { all += d.spaces }
        }
        spaces = all
        ensureSelection()
        updateBadge()
    }

    func sendText(to address: String, _ text: String) async {
        guard let c = connection else { return }
        try? await c.sendText(terminal: address, text: text)
    }
}
