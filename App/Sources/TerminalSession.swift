import Foundation
import SwiftUI
import UIKit
import SwiftTerm
import HerdrKit

final class HerdrTerminalView: TerminalView {
    var allowKeyboard = false
    var onLayout: ((HerdrTerminalView) -> Void)?
    var userEvent = false
    private let wheelDelegate = WheelPanDelegate()
    private var wheelRemainder: CGFloat = 0

    override init(frame: CGRect, font: UIFont?) {
        super.init(frame: frame, font: font)
        allowMouseReporting = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(wheelPan(_:)))
        pan.maximumNumberOfTouches = 2
        wheelDelegate.view = self
        pan.delegate = wheelDelegate
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    var wantsWheel: Bool {
        let t = getTerminal()
        return t.mouseMode != .off || t.isCurrentBufferAlternate
    }

    private var glide: CADisplayLink?
    private var glideVelocity: CGFloat = 0
    private var glidePoint: CGPoint = .zero
    private var glideLast: CFTimeInterval = 0

    @objc private func wheelPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            stopGlide()
            wheelRemainder = 0
        case .changed:
            let dy = g.translation(in: self).y
            g.setTranslation(.zero, in: self)
            wheel(dy, at: g.location(in: self))
        case .ended:
            let v = g.velocity(in: self).y
            if abs(v) > 250 { startGlide(v, at: g.location(in: self)) }
        default:
            break
        }
    }

    private func wheel(_ dy: CGFloat, at p: CGPoint) {
        let t = getTerminal()
        let rowHeight = max(bounds.height / CGFloat(max(t.rows, 1)), 4)
        wheelRemainder += dy
        let steps = Int(wheelRemainder / rowHeight)
        guard steps != 0 else { return }
        wheelRemainder -= CGFloat(steps) * rowHeight
        let col = min(max(Int(p.x / max(bounds.width / CGFloat(max(t.cols, 1)), 1)), 0), t.cols - 1)
        let row = min(max(Int((p.y - contentOffset.y) / rowHeight), 0), t.rows - 1)
        userEvent = true
        if t.mouseMode != .off {
            for _ in 0..<abs(steps) { t.sendEvent(buttonFlags: steps > 0 ? 64 : 65, x: col, y: row) }
        } else {
            let one = steps > 0 ? (t.applicationCursor ? "\u{1b}OA" : "\u{1b}[A") : (t.applicationCursor ? "\u{1b}OB" : "\u{1b}[B")
            send(txt: String(repeating: one, count: abs(steps)))
        }
        userEvent = false
    }

    private func startGlide(_ v: CGFloat, at p: CGPoint) {
        stopGlide()
        glideVelocity = min(max(v, -4000), 4000)
        glidePoint = p
        glideLast = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(glideTick(_:)))
        link.add(to: .main, forMode: .common)
        glide = link
    }

    @objc private func glideTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(max(0, min(now - glideLast, 0.05)))
        glideLast = now
        wheel(glideVelocity * dt, at: glidePoint)
        glideVelocity *= pow(0.0045, dt)
        if abs(glideVelocity) < 40 { stopGlide() }
    }

    func stopGlide() {
        glide?.invalidate()
        glide = nil
    }

    override func removeFromSuperview() {
        stopGlide()
        super.removeFromSuperview()
    }

    override var canBecomeFirstResponder: Bool { allowKeyboard }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 20, bounds.height > 20 { onLayout?(self) }
    }
}

final class WheelPanDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var view: HerdrTerminalView?

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let view, view.wantsWheel, let pan = g as? UIPanGestureRecognizer else { return false }
        let v = pan.velocity(in: view)
        return abs(v.y) >= abs(v.x)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

@MainActor
@Observable
final class TerminalSession: NSObject, TerminalViewDelegate {
    enum Status: Equatable { case idle, attaching, live, closed(String), failed(String) }

    let address: String
    @ObservationIgnored let view: HerdrTerminalView
    var status: Status = .idle
    var rawKeyboard = false {
        didSet {
            view.allowKeyboard = rawKeyboard
            if rawKeyboard { view.becomeFirstResponder() } else { view.resignFirstResponder() }
        }
    }

    @ObservationIgnored private var connection: CoreConnection?
    @ObservationIgnored private var channel: UInt32?
    @ObservationIgnored private var generation = -1
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var sentSize: (Int, Int) = (0, 0)
    @ObservationIgnored private var laidOut = false
    @ObservationIgnored private var wantAttach: (CoreConnection, Int)?
    @ObservationIgnored private var nativeSize: (Int, Int) = (0, 0)
    @ObservationIgnored private var sizeTask: Task<Void, Never>?

    @ObservationIgnored private var visibleCount = 0
    @ObservationIgnored private(set) var hiddenSince: Date? = Date()

    var isVisible: Bool { visibleCount > 0 }

    func appeared() {
        visibleCount += 1
        hiddenSince = nil
    }

    func disappeared() {
        visibleCount = max(0, visibleCount - 1)
        if visibleCount == 0 { hiddenSince = Date() }
    }

    private func pollSize(_ conn: CoreConnection, _ ch: UInt32) {
        sizeTask?.cancel()
        sizeTask = Task { [weak self, address] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.channel == ch else { return }
                guard self.isVisible, UIApplication.shared.applicationState == .active else { continue }
                guard let r = try? await conn.call("terminal.get", ["terminal": .string(address)], timeout: .seconds(5)) else { continue }
                let t = r["terminal"] ?? r
                if let c = t["cols"]?.int, let rw = t["rows"]?.int {
                    self.remoteSize(cols: c, rows: rw)
                }
            }
        }
    }
    @ObservationIgnored weak var container: TerminalContainerView?
    var mirrorSize: (cols: Int, rows: Int)?

    var cellSize: CGSize {
        let t = view.getTerminal()
        let f = view.getOptimalFrameSize()
        return CGSize(width: f.width / CGFloat(max(t.cols, 1)), height: f.height / CGFloat(max(t.rows, 1)))
    }

    func remoteSize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0, channel != nil, nativeSize != (0, 0) else { return }
        if (cols, rows) == nativeSize {
            if mirrorSize != nil {
                mirrorSize = nil
                container?.setNeedsLayout()
            }
        } else if mirrorSize.map({ $0.cols != cols || $0.rows != rows }) ?? true {
            mirrorSize = (cols, rows)
            container?.setNeedsLayout()
        }
    }

    func takeOver() {
        guard mirrorSize != nil else { return }
        mirrorSize = nil
        sentSize = (0, 0)
        container?.setNeedsLayout()
        container?.layoutIfNeeded()
        let t = view.getTerminal()
        nativeSize = (t.cols, t.rows)
        sendResizeIfNeeded(cols: t.cols, rows: t.rows)
    }

    init(address: String, fontSize: CGFloat) {
        self.address = address
        let font = ThemeStore.shared.terminalFont.uiFont(fontSize)
        view = HerdrTerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), font: font)
        super.init()
        view.terminalDelegate = self
        view.inputAccessoryView = nil
        view.optionAsMetaKey = ThemeStore.shared.optionAsMeta
        apply(palette: ThemeStore.shared.palette)
        view.onLayout = { [weak self] _ in self?.didLayout() }
    }

    func apply(palette p: Palette) {
        view.nativeBackgroundColor = UIColor(hex: p.terminal)
        view.nativeForegroundColor = UIColor(hex: p.text)
        view.backgroundColor = UIColor(hex: p.terminal)
        view.caretColor = UIColor(hex: p.accent)
        container?.backgroundColor = UIColor(hex: p.terminal)
        view.installColors(p.ansi.map { hex in
            let c = UIColor(hex: hex)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SwiftTerm.Color(red: UInt16(r * 65535), green: UInt16(g * 65535), blue: UInt16(b * 65535))
        })
        view.setNeedsDisplay()
    }

    var applicationCursor: Bool { view.getTerminal().applicationCursor }
    var bracketedPaste: Bool { view.getTerminal().bracketedPasteMode }
    var isAttached: Bool { channel != nil && status == .live }

    func setFont(size: CGFloat) {
        view.font = ThemeStore.shared.terminalFont.uiFont(size)
    }

    func setOptionAsMeta(_ on: Bool) {
        view.optionAsMetaKey = on
    }

    func ensureAttached(connection: CoreConnection?, generation: Int) {
        #if DEBUG
        if Demo.on { return }
        #endif
        guard let connection else { return }
        if generation == self.generation, channel != nil || status == .attaching { return }
        wantAttach = (connection, generation)
        if laidOut { startAttach() }
    }

    private func didLayout() {
        if !laidOut {
            laidOut = true
            #if DEBUG
            if Demo.on {
                status = .live
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self else { return }
                    self.view.feed(text: Demo.screen(self.address))
                }
                return
            }
            #endif
            if wantAttach != nil { startAttach() }
            return
        }
        guard mirrorSize == nil else { return }
        let t = view.getTerminal()
        nativeSize = (t.cols, t.rows)
        sendResizeIfNeeded(cols: t.cols, rows: t.rows)
    }

    private func startAttach() {
        guard let (conn, gen) = wantAttach else { return }
        wantAttach = nil
        readTask?.cancel()
        if let old = connection, let ch = channel {
            Task { await old.closeChannel(ch) }
        }
        connection = conn
        generation = gen
        channel = nil
        status = .attaching
        if mirrorSize != nil {
            mirrorSize = nil
            container?.setNeedsLayout()
            container?.layoutIfNeeded()
        }
        let t = view.getTerminal()
        let cols = max(t.cols, 20)
        let rows = max(t.rows, 5)
        view.getTerminal().resetToInitialState()
        readTask = Task { [weak self, address] in
            do {
                let att = try await conn.attach(terminal: address, cols: cols, rows: rows, history: 1500)
                guard let self else { return }
                self.channel = att.channel
                self.sentSize = (cols, rows)
                self.nativeSize = (cols, rows)
                self.status = .live
                self.pollSize(conn, att.channel)
                await conn.focus(channel: att.channel, true)
                let now = self.view.getTerminal()
                self.sendResizeIfNeeded(cols: now.cols, rows: now.rows)
                for await m in att.stream {
                    if Task.isCancelled { return }
                    switch m {
                    case .data(let d):
                        self.view.feed(byteArray: ArraySlice([UInt8](d)))
                        await conn.credit(channel: att.channel, bytes: d.count)
                    case .close(let info):
                        let reason = info?["reason"]?.string ?? "closed"
                        self.status = .closed(reason)
                        self.channel = nil
                        return
                    default:
                        break
                    }
                }
                if self.channel == att.channel {
                    self.channel = nil
                    if case .live = self.status { self.status = .closed("disconnected") }
                }
            } catch {
                self?.status = .failed(AppModel.describe(error))
                self?.channel = nil
            }
        }
    }

    private func sendResizeIfNeeded(cols: Int, rows: Int) {
        guard mirrorSize == nil, let conn = connection, let ch = channel, cols > 0, rows > 0 else { return }
        nativeSize = (cols, rows)
        if sentSize == (cols, rows) { return }
        sentSize = (cols, rows)
        Task { await conn.resize(channel: ch, cols: cols, rows: rows) }
    }

    func detach() {
        readTask?.cancel()
        readTask = nil
        sizeTask?.cancel()
        sizeTask = nil
        if let conn = connection, let ch = channel {
            Task { await conn.closeChannel(ch) }
        }
        channel = nil
        generation = -1
        status = .idle
    }

    func send(_ bytes: Data) {
        guard let conn = connection, let ch = channel else { return }
        takeOver()
        Task {
            await conn.focus(channel: ch, true)
            await conn.input(channel: ch, bytes)
        }
    }

    func send(_ text: String) { send(Data(text.utf8)) }

    func paste(_ text: String, submit: Bool) async {
        guard let conn = connection, let ch = channel else { return }
        takeOver()
        let body = bracketedPaste ? "\u{1b}[200~" + text + "\u{1b}[201~" : text
        await conn.focus(channel: ch, true)
        await conn.input(channel: ch, Data(body.utf8))
        if submit {
            try? await Task.sleep(for: .milliseconds(60))
            await conn.input(channel: ch, Data("\r".utf8))
        }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Task { @MainActor in self.sendResizeIfNeeded(cols: newCols, rows: newRows) }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let d = Data(data)
        let user = Thread.isMainThread && MainActor.assumeIsolated { (source as? HerdrTerminalView)?.userEvent ?? false }
        Task { @MainActor in
            guard let conn = self.connection, let ch = self.channel else { return }
            if self.rawKeyboard || user {
                if self.rawKeyboard && !user { self.takeOver() }
                await conn.input(channel: ch, d)
            } else {
                await conn.automaticInput(channel: ch, d)
            }
        }
    }

    nonisolated func scrolled(source: TerminalView, position: Double) {}

    nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme ?? "") else { return }
        Task { @MainActor in UIApplication.shared.open(url) }
    }

    nonisolated func bell(source: TerminalView) {}

    nonisolated func clipboardCopy(source: TerminalView, content: Data) {
        if let s = String(data: content, encoding: .utf8) {
            Task { @MainActor in UIPasteboard.general.string = s }
        }
    }

    nonisolated func clipboardRead(source: TerminalView) -> Data? { nil }

    nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

@MainActor
final class SessionPool {
    private var sessions: [String: TerminalSession] = [:]
    private var lru: [String] = []
    let limit = 8

    private var reaper: Task<Void, Never>?

    func session(for address: String, fontSize: CGFloat) -> TerminalSession {
        startReaper()
        if let s = sessions[address] {
            touch(address)
            return s
        }
        let s = TerminalSession(address: address, fontSize: fontSize)
        sessions[address] = s
        touch(address)
        while lru.count > limit, let victim = lru.first {
            lru.removeFirst()
            sessions.removeValue(forKey: victim)?.detach()
        }
        return s
    }

    private func startReaper() {
        guard reaper == nil else { return }
        reaper = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                for s in self.sessions.values where s.status == .live {
                    if let since = s.hiddenSince, Date().timeIntervalSince(since) > 180 { s.detach() }
                }
            }
        }
    }

    func existing(_ address: String) -> TerminalSession? { sessions[address] }

    func dismissKeyboards() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        for s in sessions.values where s.rawKeyboard { s.rawKeyboard = false }
    }

    func setFont(size: CGFloat) {
        for s in sessions.values { s.setFont(size: size) }
    }

    func setOptionAsMeta(_ on: Bool) {
        for s in sessions.values { s.setOptionAsMeta(on) }
    }

    func apply(palette: Palette) {
        for s in sessions.values { s.apply(palette: palette) }
    }

    func detachAll() {
        for s in sessions.values { s.detach() }
    }

    private func touch(_ a: String) {
        lru.removeAll { $0 == a }
        lru.append(a)
    }
}

final class TerminalContainerView: UIView {
    weak var session: TerminalSession?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let s = session, s.view.superview === self else { return }
        let v = s.view
        let area = bounds.inset(by: UIEdgeInsets(top: 2, left: 4, bottom: 0, right: 2))
        guard area.width > 0, area.height > 0 else { return }
        if let m = s.mirrorSize {
            let cell = s.cellSize
            let size = CGSize(width: (CGFloat(m.cols) + 0.5) * cell.width, height: (CGFloat(m.rows) + 0.5) * cell.height)
            let scale = min(1, area.width / size.width, area.height / size.height)
            v.transform = .identity
            v.bounds.size = size
            v.transform = CGAffineTransform(scaleX: scale, y: scale)
            v.center = CGPoint(x: area.minX + size.width * scale / 2, y: area.minY + size.height * scale / 2)
        } else {
            v.transform = .identity
            v.frame = area
        }
    }
}

struct TerminalPaneView: UIViewRepresentable {
    let session: TerminalSession

    func makeUIView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.backgroundColor = UIColor(hex: ThemeStore.shared.palette.terminal)
        mount(session, in: container)
        return container
    }

    func updateUIView(_ container: TerminalContainerView, context: Context) {
        if session.view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            mount(session, in: container)
        }
        container.setNeedsLayout()
    }

    private func mount(_ s: TerminalSession, in container: TerminalContainerView) {
        s.view.removeFromSuperview()
        s.view.translatesAutoresizingMaskIntoConstraints = true
        container.session = s
        s.container = container
        container.addSubview(s.view)
        container.setNeedsLayout()
    }
}
