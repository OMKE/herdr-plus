import Foundation
import UIKit
import Observation
import HerdrKit

@MainActor
@Observable
final class ChatController {
    enum Phase: Equatable {
        case locating
        case ready
        case noLog(String)
    }

    let address: String
    var phase: Phase = .locating
    var rows: [ChatRow] = []
    var model: String?
    var card: ChatCard?
    var busy = false
    var notice: String?
    var sending = false
    var commands: [SlashCommand] = []
    var usage: AgentUsage?
    var branch: String?
    var alwaysLabel: String?
    var draft = ""
    var draftImages: [DraftImage] = []
    var draftCommand: String?
    var questionOther = ""
    var questionSubmit = 0
    var earlierStart = -1
    var loadingEarlier = false
    var queue: [QueuedMessage] = []
    var logID = 0
    var panel: TUIPanel?
    var activity: ScreenActivity?
    var canLoadEarlier: Bool { earlierStart > 0 || !previous.isEmpty }
    var lastSendAt: Date { lastSend }
    @ObservationIgnored private var locatedPath: String?
    @ObservationIgnored private var previous: [(path: String, end: Int)] = []
    @ObservationIgnored private var earlierPath: String?
    private var logRows: [ChatRow] = []
    private var pendingRows: [(row: ChatRow, at: Date, key: String)] = []
    @ObservationIgnored private var earlierItems: [ChatItem] = []
    @ObservationIgnored private var earlierParsers: [ConversationParser] = []
    @ObservationIgnored private var tailStart = -1
    @ObservationIgnored private var autoLoaded = false
    @ObservationIgnored private var lastBranch = Date.distantPast

    @ObservationIgnored private var log: AgentLog?
    @ObservationIgnored private var kicked = false
    @ObservationIgnored private var lastSend = Date.distantPast
    @ObservationIgnored private var lastUsage = Date.distantPast
    @ObservationIgnored private var commandsFor: String?
    @ObservationIgnored private var imageCache: [String: UIImage] = [:]
    @ObservationIgnored private var tail: LogTail?
    @ObservationIgnored private var hops = 0
    @ObservationIgnored private var rowsBlocked = false
    @ObservationIgnored private var lastLocate = Date.distantPast
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var visible = 0
    @ObservationIgnored private weak var app: AppModel?

    init(address: String, app: AppModel) {
        self.address = address
        self.app = app
    }

    var terminal: Terminal? { app?.store[address] }
    var connection: CoreConnection? { app?.connection }

    func appear() {
        visible += 1
        if phase != .ready { lastLocate = .distantPast }
        kick()
        if let l = loop, !l.isCancelled { return }
        loop = Task { [weak self] in await self?.run() }
    }

    func disappear() {
        visible = max(0, visible - 1)
        if visible == 0 { loop?.cancel(); loop = nil }
    }

    func refresh() {
        lastLocate = .distantPast
        tail = nil
        log = nil
        locatedPath = nil
        previous = []
        commandsFor = nil
        clearRows()
        phase = .locating
        loop?.cancel()
        loop = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        var tick = 0
        while !Task.isCancelled {
            if UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let before = terminal?.agentState
            await step(tick: tick)
            await flushQueue()
            tick += 1
            let busy = before == .working || before == .blocked || activity != nil
            let recent = Date().timeIntervalSince(lastSend) < 30 || !pendingRows.isEmpty
            let until = Date().addingTimeInterval(busy || recent ? 0.6 : 1.5)
            while !Task.isCancelled, Date() < until {
                try? await Task.sleep(for: .milliseconds(100))
                if kicked || terminal?.agentState != before { break }
            }
            kicked = false
        }
    }

    func kick() { kicked = true }

    func image(_ key: String) -> UIImage? {
        if let i = imageCache[key] { return i }
        guard let data = tail?.parser.imageData(key) ?? earlierParsers.lazy.compactMap({ $0.imageData(key) }).first, let img = UIImage(data: data) else { return nil }
        let thumb = img.preparingThumbnail(of: CGSize(width: 900, height: 900 * img.size.height / max(img.size.width, 1))) ?? img
        imageCache[key] = thumb
        return thumb
    }

    private func publish() {
        let now = Date()
        pendingRows.removeAll { p in
            if now.timeIntervalSince(p.at) > 90 { return true }
            return logRows.contains { r in
                guard case .user(let text, _) = r.kind, (r.timestamp ?? now) >= p.at.addingTimeInterval(-5) else { return false }
                let flat = Questions.flat(text)
                return p.key.isEmpty ? r.images > 0 : flat.contains(p.key) || p.key.contains(flat.prefix(40))
            }
        }
        rows = logRows + pendingRows.map(\.row)
    }

    private func resetEarlier(_ start: Int) {
        earlierItems = []
        earlierParsers = []
        earlierStart = start
        earlierPath = tail?.path
        tailStart = start
        autoLoaded = false
    }

    private func clearRows() {
        logRows = []
        rows = pendingRows.map(\.row)
        resetEarlier(-1)
        logID += 1
        phase = .locating
    }

    private func rebuild() {
        logRows = ChatRows.build(earlierItems + (tail?.parser.items(awaitingApproval: rowsBlocked) ?? []))
        publish()
    }

    private var wantsEarlier: Bool {
        guard canLoadEarlier, !autoLoaded else { return false }
        let items = earlierItems + (tail?.parser.items(awaitingApproval: false) ?? [])
        let users = items.filter { if case .user = $0.kind { true } else { false } }.count
        let compacted = items.contains { if case .status(let s) = $0.kind { s == "Context compacted" } else { false } }
        return compacted || users < 3
    }

    func loadEarlier() async {
        guard let c = connection, let log, tail != nil, canLoadEarlier, !loadingEarlier else { return }
        if earlierStart <= 0, let prev = previous.popLast() {
            earlierPath = prev.path
            earlierStart = prev.end
        }
        guard let path = earlierPath, earlierStart > 0 else { return }
        let id = logID
        loadingEarlier = true
        defer { loadingEarlier = false }
        do {
            let r = try await LogTail.earlier(path: path, before: earlierStart, via: c, on: log.machine)
            guard logID == id, earlierPath == path else { return }
            earlierParsers.insert(r.parser, at: 0)
            earlierItems = r.parser.items(awaitingApproval: false) + earlierItems
            earlierStart = r.start
            rebuild()
        } catch {
            notice = "Couldn't load earlier messages: \(AppModel.describe(error))"
        }
    }

    private func addPending(text: String, images: Int, thumbs: [UIImage] = []) {
        let key = String(Questions.flat(text).prefix(40))
        let id = "pending-\(UUID().uuidString)"
        var keys: [String] = []
        for (i, t) in thumbs.enumerated() {
            imageCache["\(id)-\(i)"] = t
            keys.append("\(id)-\(i)")
        }
        let row = ChatRow(id: id, kind: .user(text: text, from: nil), timestamp: Date(), images: images, imageKeys: keys, pending: true)
        pendingRows.append((row, Date(), key))
        publish()
    }

    private func refreshExtras(_ c: CoreConnection, _ t: Terminal) async {
        guard let log else { return }
        if commandsFor != log.path {
            commandsFor = log.path
            commands = await SlashCommands.load(kind: log.kind, configDir: log.dir, cwd: t.foreground?.cwd ?? t.cwd, via: c, on: log.machine)
        }
        if log.kind == .claude, let pid = log.pid, Date().timeIntervalSince(lastUsage) > 8 {
            lastUsage = Date()
            if let u = try? await UsageReader.session(pid: pid, via: c, on: log.machine) { usage = u }
        }
        if Date().timeIntervalSince(lastBranch) > 30 {
            lastBranch = Date()
            let dir = t.foreground?.cwd ?? t.cwd
            if !dir.isEmpty, let r = try? await c.shell(#"git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null"#, [dir], on: log.machine, timeout: .seconds(8)), r.code == 0 {
                let b = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                branch = b.isEmpty || b == "HEAD" ? nil : b
            }
        }
    }

    private func step(tick: Int) async {
        guard let c = connection, let t = terminal else { return }
        if log == nil && Date().timeIntervalSince(lastLocate) > 5 || Date().timeIntervalSince(lastLocate) > 30 {
            lastLocate = Date()
            do {
                if let found = try await Locator.locate(t, via: c) {
                    if found.path != locatedPath {
                        locatedPath = found.path
                        log = found
                        tail = LogTail(path: found.path)
                        hops = 0
                        previous = []
                        clearRows()
                    }
                } else if log == nil {
                    phase = .noLog(Locator.agentKind(t) == nil ? "This terminal has no Claude or Codex agent." : "Can't find this agent's session log yet.")
                }
            } catch {
                if log == nil { phase = .noLog("Can't read the session: \(AppModel.describe(error))") }
            }
        }
        if var tl = tail, let log {
            do {
                let blocked = t.agentState == .blocked
                if try await tl.poll(via: c, on: log.machine) || blocked != rowsBlocked {
                    if let next = tl.parser.continuedIn, hops < 16, let dir = log.dir,
                       let p = try await Locator.find(sid: next, dir: dir, via: c, on: log.machine) {
                        hops += 1
                        previous.append((tl.path, tl.offset))
                        self.log = AgentLog(kind: log.kind, path: p, dir: dir, machine: log.machine, pid: log.pid)
                        tail = LogTail(path: p)
                        clearRows()
                        kick()
                        return
                    }
                    tail = tl
                    rowsBlocked = blocked
                    if tl.start != tailStart { resetEarlier(tl.start) }
                    rebuild()
                    model = tl.parser.model
                    if wantsEarlier {
                        autoLoaded = true
                        phase = .ready
                        await loadEarlier()
                    }
                } else if !pendingRows.isEmpty {
                    publish()
                }
                tail = tl
                phase = .ready
            } catch {
                tail = LogTail(path: log.path)
            }
        }
        if panel != nil { await refreshPanel() } else { await updateCard(c, t) }
        await refreshActivity(c, t)
        await refreshExtras(c, t)
    }

    private var turnOpen: Bool {
        guard let last = logRows.last else { return false }
        if case .footer = last.kind { return false }
        return true
    }

    private func refreshActivity(_ c: CoreConnection, _ t: Terminal) async {
        let recent = Date().timeIntervalSince(lastSend) < 30 || !pendingRows.isEmpty
        guard panel == nil, t.agentState != .blocked, t.agentState == .working || turnOpen || recent else {
            if activity != nil { activity = nil }
            return
        }
        let next = (try? await c.screen(terminal: address)).flatMap(ScreenActivity.parse)
        if next != activity { activity = next }
    }

    private var pendingLogQuestion: QuestionRequest? {
        for r in rows.reversed() {
            if case .question(let q) = r.kind { return q.state == .pending ? q : nil }
            if case .user = r.kind { return nil }
        }
        return nil
    }

    private func updateCard(_ c: CoreConnection, _ t: Terminal) async {
        if busy { return }
        let kind = Locator.agentKind(t)
        let logQ = pendingLogQuestion
        if kind == .codex, let q = logQ, q.delivery == .message {
            card = .question(q)
            return
        }
        guard t.agentState == .blocked else { card = nil; return }
        guard let screen = try? await c.screen(terminal: address) else { return }
        let statusKind = t.status?.kind
        if statusKind != "question", let a = ScreenCards.approval(screen) {
            alwaysLabel = Self.alwaysOption(screen)
            card = .approval(a)
            return
        }
        if kind == .claude, statusKind != "permission" {
            if Questions.showsReview(screen) { card = .review("Review your answers"); return }
            if let q = Questions.screenRequest(screen) {
                if case .question(let old)? = card, old.toolUseId == q.toolUseId { return }
                card = .question(logQ.flatMap { merged(log: $0, screen: q) } ?? q)
                return
            }
        }
        if kind == .codex, let q = logQ, Questions.showsCodex(q, screen: screen) {
            card = .question(q)
            return
        }
        card = nil
    }

    private func merged(log: QuestionRequest, screen: QuestionRequest) -> QuestionRequest? {
        guard let sq = screen.questions.first,
              let lq = log.questions.first(where: { Questions.flat($0.text) == Questions.flat(sq.text) }),
              lq.options.map({ Questions.flat($0.label) }) == sq.options.map({ Questions.flat($0.label) }) else { return nil }
        var out = screen
        out.questions = [QuestionRequest.Question(id: sq.id, header: sq.header, text: sq.text,
                                                  options: zip(sq.options, lq.options).map { s, l in
                                                      QuestionRequest.Option(label: s.label, detail: l.detail.isEmpty ? s.detail : l.detail, recommended: s.recommended || l.recommended)
                                                  }, multiSelect: sq.multiSelect)]
        return out
    }

    static func alwaysOption(_ screen: String) -> String? {
        guard let m = screen.firstMatch(of: /2\.\s+(Yes,[^\n]+)/) else { return nil }
        let s = String(m.1).trimmingCharacters(in: CharacterSet(charactersIn: "│| ").union(.whitespaces))
        return s.isEmpty ? nil : s
    }

    func approve(_ card: ApprovalCard, allow: Bool) async {
        await press(card, allow ? "1" : "esc")
    }

    func approveAlways(_ card: ApprovalCard) async {
        await press(card, "2", needsAlways: true)
    }

    func sendKey(_ name: String) async {
        guard let c = connection else { return }
        do {
            try await c.keys(terminal: address, [name])
            kick()
        } catch {
            notice = "Couldn't send \(name): \(AppModel.describe(error))"
        }
    }

    private func press(_ card: ApprovalCard, _ key: String, needsAlways: Bool = false) async {
        guard let c = connection, !busy else { return }
        busy = true
        defer { busy = false }
        guard let screen = try? await c.screen(terminal: address), ScreenCards.approval(screen)?.id == card.id,
              !needsAlways || Self.alwaysOption(screen) != nil else {
            notice = "The prompt changed. Nothing was sent."
            self.card = nil
            return
        }
        do {
            try await c.keys(terminal: address, [key])
            self.card = nil
            try? await Task.sleep(for: .milliseconds(600))
        } catch CoreError.timeout {
            notice = "Sent, but the agent hasn't confirmed yet."
        } catch {
            notice = "Couldn't send: \(AppModel.describe(error))"
        }
    }

    func submitReview() async {
        guard let c = connection, !busy else { return }
        busy = true
        defer { busy = false }
        guard let screen = try? await c.screen(terminal: address), Questions.showsReview(screen) else {
            notice = "The review screen is gone. Nothing was sent."
            card = nil
            return
        }
        try? await c.keys(terminal: address, ["1"])
        card = nil
    }

    func answer(_ q: QuestionRequest, _ answers: [QuestionAnswer]) async {
        guard let c = connection, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if q.delivery == .message {
                try await c.sendText(terminal: address, text: Questions.messageText(for: q, answers: answers))
                card = nil
                return
            }
            let steps = try Questions.steps(for: q, answers: answers)
            let screen = try await c.screen(terminal: address)
            if q.isFromScreen {
                guard Questions.screenRequest(screen)?.toolUseId == q.toolUseId else { throw Questions.Failure.notOnScreen }
            } else if q.agent == "codex" {
                guard Questions.showsCodex(q, screen: screen) else { throw Questions.Failure.notOnScreen }
            }
            for s in steps {
                switch s {
                case .text(let text):
                    try await c.keys(terminal: address, text.map { String($0) })
                case .keys(let k):
                    try await c.keys(terminal: address, k)
                case .waitFor(let needle):
                    var ok = false
                    for _ in 0..<25 {
                        try await Task.sleep(for: .milliseconds(200))
                        let now = try await c.screen(terminal: address)
                        if let region = Questions.pickerRegion(agent: q.agent, screen: now), region.contains(needle) { ok = true; break }
                    }
                    if !ok { throw Questions.Failure.stuck(needle) }
                }
                try await Task.sleep(for: .milliseconds(120))
            }
            card = nil
        } catch let f as Questions.Failure {
            notice = f.description
            card = nil
        } catch {
            notice = "Couldn't send: \(AppModel.describe(error))"
        }
    }

    func send(text: String, images: [(name: String, data: Data)], thumbs: [UIImage] = []) async -> Bool {
        guard let c = connection, !sending else { return false }
        sending = true
        defer { sending = false }
        var parts: [String] = []
        do {
            for img in images {
                let path = try await c.put(terminal: address, name: img.name, data: img.data)
                if !path.isEmpty { parts.append(Self.quote(path)) }
            }
        } catch {
            notice = "Couldn't upload the image: \(AppModel.describe(error))"
            return false
        }
        let body = ([text.trimmingCharacters(in: .whitespacesAndNewlines)] + parts).filter { !$0.isEmpty }.joined(separator: " ")
        guard !body.isEmpty else { return false }
        do {
            lastSend = Date()
            addPending(text: text.trimmingCharacters(in: .whitespacesAndNewlines), images: images.count, thumbs: thumbs)
            try await c.sendText(terminal: address, text: body)
            kick()
            return true
        } catch CoreError.timeout {
            notice = "Sent, but the agent hasn't confirmed yet."
            kick()
            return true
        } catch {
            if !pendingRows.isEmpty { pendingRows.removeLast() }
            publish()
            notice = "Couldn't send: \(AppModel.describe(error))"
            return false
        }
    }

    func runCommand(_ name: String, args: String) async -> Bool {
        guard let c = connection, !sending else { return false }
        sending = true
        defer { sending = false }
        let line = "/" + name + (args.isEmpty ? "" : " " + args)
        let shows = terminal.flatMap { Locator.agentKind($0) }.map { SlashCommands.showsPanel(name, kind: $0) } ?? false
        do {
            lastSend = Date()
            try await c.sendText(terminal: address, text: line)
            if shows { panel = TUIPanel(command: line, screen: "") }
            kick()
            return true
        } catch CoreError.timeout {
            if shows { panel = TUIPanel(command: line, screen: "") }
            kick()
            return true
        } catch {
            notice = "Couldn't run /\(name): \(AppModel.describe(error))"
            return false
        }
    }

    func interrupt() async {
        guard let c = connection else { return }
        try? await c.keys(terminal: address, ["esc"])
    }

    func panelKey(_ key: String) async {
        guard let c = connection else { return }
        try? await c.keys(terminal: address, [key])
        try? await Task.sleep(for: .milliseconds(150))
        await refreshPanel()
    }

    func closePanel() async {
        guard let c = connection, panel != nil else { return }
        panel = nil
        try? await c.keys(terminal: address, ["esc"])
        kick()
    }

    func refreshPanel() async {
        guard let c = connection, panel != nil, let screen = try? await c.screen(terminal: address) else { return }
        let lines = screen.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        var end = lines.count
        while end > 0, lines[end - 1].isEmpty { end -= 1 }
        let text = lines[..<end].suffix(60).joined(separator: "\n")
        if panel != nil, panel?.screen != text { panel?.screen = text }
    }

    static func quote(_ path: String) -> String {
        path.contains(where: { $0 == " " || $0 == "'" || $0 == "\"" }) ? "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" : path
    }
}

struct TUIPanel: Equatable {
    var command: String
    var screen: String
}

struct QueuedMessage: Identifiable {
    let id = UUID()
    var text: String
    var images: [DraftImage]
    let at = Date()
}

extension ChatController {
    var agentBusy: Bool { terminal?.agentState == .working }
    var showsWorking: Bool {
        guard let s = terminal?.agentState, s != .blocked else { return false }
        return s == .working || activity != nil || ChatRows.toolRunning(logRows)
    }

    func enqueue(text: String, images: [DraftImage]) {
        queue.append(QueuedMessage(text: text.trimmingCharacters(in: .whitespacesAndNewlines), images: images))
        kick()
    }

    func cancelQueued(_ id: UUID) {
        queue.removeAll { $0.id == id }
    }

    func editQueued(_ id: UUID) {
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        let m = queue.remove(at: i)
        let current = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = current.isEmpty ? m.text : m.text + "\n" + current
        draftImages = m.images + draftImages
    }

    func sendNow(_ id: UUID) async {
        guard let i = queue.firstIndex(where: { $0.id == id }), !sending else { return }
        let m = queue[i]
        if await send(text: m.text, images: m.images.map { (name: $0.name, data: $0.data) }, thumbs: m.images.map(\.thumb)) {
            queue.removeAll { $0.id == id }
        }
    }

    func flushQueue() async {
        guard let first = queue.first, !sending, let s = terminal?.agentState, s == .done || s == .idle else { return }
        guard Date().timeIntervalSince(lastSendAt) > 4 else { return }
        await sendNow(first.id)
    }
}

struct DraftImage: Identifiable {
    let id = UUID()
    let name: String
    let data: Data
    let thumb: UIImage
}

@MainActor
final class ChatPool {
    private var chats: [String: ChatController] = [:]

    func chat(for address: String, app: AppModel) -> ChatController {
        if let c = chats[address] { return c }
        let c = ChatController(address: address, app: app)
        chats[address] = c
        return c
    }
}
