import Foundation

public protocol ByteTransport: AnyObject, Sendable {
    func send(_ data: Data) async throws
    var incoming: AsyncThrowingStream<Data, Error> { get }
    func close() async
}

public struct RPCError: Error, Sendable, CustomStringConvertible {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public var description: String { message }
}

public enum CoreError: Error, Sendable, CustomStringConvertible {
    case disconnected
    case badResponse(String)
    case timeout

    public var description: String {
        switch self {
        case .disconnected: "Connection closed"
        case .badResponse(let s): "Unexpected response: \(s)"
        case .timeout: "Timed out"
        }
    }
}

public enum ChannelMessage: Sendable {
    case data(Data)
    case close(JSONValue?)
    case resize(cols: Int, rows: Int)
    case other(kind: UInt8, payload: Data)
}

public struct Attachment: Sendable {
    public var channel: UInt32
    public var terminal: JSONValue
    public var automaticInput: Bool
    public var resizeNotifications: Bool
    public var stream: AsyncStream<ChannelMessage>
}

public struct EventSubscription: Sendable {
    public var channel: UInt32
    public var seq: UInt64
    public var terminals: [Terminal]
    public var stream: AsyncStream<CoreNotification>
}

public actor CoreConnection {
    private let transport: ByteTransport
    private var nextId = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var routes: [UInt32: AsyncStream<ChannelMessage>.Continuation] = [:]
    private var early: [UInt32: [ChannelMessage]] = [:]
    private var automaticInputChannels = Set<UInt32>()
    private var framed = false
    private var switchAfter: Int?
    private var lines = LineDecoder()
    private var frames = FrameDecoder()
    private var readTask: Task<Void, Never>?
    private var closed = false
    private var closeHandlers: [@Sendable (Error?) -> Void] = []
    public private(set) var info: CoreInfo?

    public init(transport: ByteTransport) {
        self.transport = transport
    }

    public var isClosed: Bool { closed }

    public func onClose(_ handler: @escaping @Sendable (Error?) -> Void) {
        if closed { handler(nil); return }
        closeHandlers.append(handler)
    }

    public func start() async throws -> CoreInfo {
        let stream = transport.incoming
        readTask = Task { [weak self] in
            do {
                for try await chunk in stream {
                    guard let self else { return }
                    await self.ingest(chunk)
                }
                await self?.shutdown(nil)
            } catch {
                await self?.shutdown(error)
            }
        }
        let hello = try await call("hello", ["generation": 1])
        let framedHello = try await call("hello", ["generation": 1, "framed": true], switchToFramed: true)
        let src = framedHello.object != nil ? framedHello : hello
        let core = src["core"] ?? src
        let i = CoreInfo(
            id: core["id"]?.string ?? src["id"]?.string ?? "",
            name: core["name"]?.string ?? src["name"]?.string ?? "",
            version: core["version"]?.string ?? src["version"]?.string ?? "",
            generation: src["generation"]?.int ?? 1,
            features: (src["features"]?.array ?? hello["features"]?.array ?? []).compactMap(\.string)
        )
        info = i
        return i
    }

    public func call(_ method: String, _ params: JSONValue = [:], timeout: Duration = .seconds(30)) async throws -> JSONValue {
        try await call(method, params, switchToFramed: false, timeout: timeout)
    }

    private func call(_ method: String, _ params: JSONValue, switchToFramed: Bool, timeout: Duration = .seconds(30)) async throws -> JSONValue {
        if closed { throw CoreError.disconnected }
        nextId += 1
        let id = nextId
        let message: JSONValue = ["jsonrpc": "2.0", "id": .number(Double(id)), "method": .string(method), "params": params]
        var body = try message.data()
        if switchToFramed { switchAfter = id }
        let wasFramed = framed
        if wasFramed {
            body = Frame(channel: 0, kind: .data, payload: body).encoded()
        } else {
            body.append(0x0A)
        }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.fail(id: id, error: CoreError.timeout)
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            Task {
                do {
                    try await transport.send(body)
                } catch {
                    self.fail(id: id, error: error)
                }
            }
        }
    }

    private func fail(id: Int, error: Error) {
        if let c = pending.removeValue(forKey: id) { c.resume(throwing: error) }
    }

    public func send(channel: UInt32, kind: FrameKind, payload: Data) async {
        guard framed, !closed else { return }
        try? await transport.send(Frame(channel: channel, kind: kind, payload: payload).encoded())
    }

    public func input(channel: UInt32, _ bytes: Data) async {
        guard !bytes.isEmpty else { return }
        await send(channel: channel, kind: .data, payload: bytes)
    }

    public func automaticInput(channel: UInt32, _ bytes: Data) async {
        guard !bytes.isEmpty else { return }
        await send(channel: channel, kind: automaticInputChannels.contains(channel) ? .automaticInput : .data, payload: bytes)
    }

    public func resize(channel: UInt32, cols: Int, rows: Int) async {
        await send(channel: channel, kind: .resize, payload: Frame.resize(channel: channel, cols: UInt16(clamping: cols), rows: UInt16(clamping: rows)).payload)
    }

    public func focus(channel: UInt32, _ focused: Bool) async {
        await send(channel: channel, kind: .focus, payload: Data([focused ? 1 : 0]))
    }

    public func credit(channel: UInt32, bytes: Int) async {
        var p = Data()
        p.appendLE(UInt32(clamping: bytes))
        await send(channel: channel, kind: .credit, payload: p)
    }

    public func closeChannel(_ channel: UInt32) async {
        await send(channel: channel, kind: .close, payload: Data())
        routes.removeValue(forKey: channel)?.finish()
        automaticInputChannels.remove(channel)
    }

    private func register(_ channel: UInt32) -> AsyncStream<ChannelMessage> {
        let (stream, cont) = AsyncStream<ChannelMessage>.makeStream()
        for m in early.removeValue(forKey: channel) ?? [] { cont.yield(m) }
        routes[channel] = cont
        return stream
    }

    public func subscribeEvents() async throws -> EventSubscription {
        let result = try await call("events.subscribe", [:])
        guard let ch = result["channel"]?.int else { throw CoreError.badResponse("events.subscribe") }
        let channel = UInt32(ch)
        let raw = register(channel)
        await credit(channel: channel, bytes: 1024 * 1024)
        let (stream, cont) = AsyncStream<CoreNotification>.makeStream()
        Task { [weak self] in
            var decoder = LineDecoder()
            for await m in raw {
                switch m {
                case .data(let d):
                    for line in decoder.push(d) {
                        if let json = try? JSONDecoder().decode(JSONValue.self, from: line), let n = CoreNotification.parse(json) {
                            cont.yield(n)
                        }
                    }
                    await self?.credit(channel: channel, bytes: d.count)
                case .close:
                    cont.finish()
                    return
                default:
                    break
                }
            }
            cont.finish()
        }
        return EventSubscription(
            channel: channel,
            seq: UInt64(result["seq"]?.double ?? 0),
            terminals: (result["terminals"]?.array ?? []).map(Terminal.init(json:)),
            stream: stream
        )
    }

    public func attach(terminal: String, cols: Int, rows: Int, history: Int = 2000, display: JSONValue = [:]) async throws -> Attachment {
        let result = try await call("terminal.attach", ["terminal": .string(terminal), "cols": .number(Double(cols)), "rows": .number(Double(rows)), "history": .number(Double(history)), "display": display])
        guard let ch = result["channel"]?.int else { throw CoreError.badResponse("terminal.attach") }
        let channel = UInt32(ch)
        let auto = result["automatic_input"]?.bool == true && (info?.features.contains("automatic_input") ?? true)
        if auto { automaticInputChannels.insert(channel) }
        let stream = register(channel)
        return Attachment(
            channel: channel,
            terminal: result["terminal"] ?? .null,
            automaticInput: auto,
            resizeNotifications: result["resize_notifications"]?.bool ?? false,
            stream: stream
        )
    }

    public func terminals() async throws -> [Terminal] {
        let r = try await call("terminal.list", [:])
        return (r["terminals"]?.array ?? []).map(Terminal.init(json:))
    }

    public func machines() async throws -> [Machine] {
        let r = try await call("machine.list", [:])
        return (r["machines"]?.array ?? []).map(Machine.init(json:))
    }

    public func layout(on machine: String? = nil) async throws -> LayoutDocument {
        var params: JSONValue = ["name": "herdr-app"]
        if let machine, case .object(var o) = params {
            o["on"] = .string(machine)
            params = .object(o)
        }
        let r = try await call("doc.get", params)
        return LayoutDocument(value: r["value"] ?? .null, version: r["version"]?.int ?? 0, machine: machine)
    }

    public func read(terminal: String, lines: Int = 40) async throws -> String {
        let r = try await call("terminal.read", ["terminal": .string(terminal), "lines": .number(Double(lines))])
        return r["text"]?.string ?? ""
    }

    public func sendText(terminal: String, text: String, force: Bool = false) async throws {
        _ = try await call("terminal.send", ["terminal": .string(terminal), "text": .string(text), "force": .bool(force)], timeout: .seconds(75))
    }

    public func close() async {
        await transport.close()
        shutdown(nil)
    }

    private func shutdown(_ error: Error?) {
        guard !closed else { return }
        closed = true
        for (_, c) in pending { c.resume(throwing: error ?? CoreError.disconnected) }
        pending.removeAll()
        for (_, r) in routes { r.yield(.close(nil)); r.finish() }
        routes.removeAll()
        let handlers = closeHandlers
        closeHandlers.removeAll()
        for h in handlers { h(error) }
    }

    private func ingest(_ chunk: Data) {
        if !framed {
            for line in lines.push(chunk) {
                handleRPC(line)
                if framed {
                    let rest = lines.takeRemainder()
                    if !rest.isEmpty { ingestFrames(rest) }
                    return
                }
            }
        } else {
            ingestFrames(chunk)
        }
    }

    private func ingestFrames(_ data: Data) {
        do {
            for f in try frames.push(data) { route(f) }
        } catch {
            shutdown(error)
            Task { await transport.close() }
        }
    }

    private func route(_ f: Frame) {
        if f.channel == 0 {
            if f.kind == FrameKind.data.rawValue {
                var dec = LineDecoder()
                let parts = dec.push(f.payload + Data([0x0A]))
                for p in parts { handleRPC(p) }
            }
            return
        }
        let message: ChannelMessage
        switch f.frameKind {
        case .data:
            message = .data(f.payload)
        case .close:
            message = .close(try? JSONDecoder().decode(JSONValue.self, from: f.payload))
        case .resize where f.payload.count >= 4:
            let cols = Int(f.payload.readLE(UInt16.self, at: f.payload.startIndex))
            let rows = Int(f.payload.readLE(UInt16.self, at: f.payload.startIndex + 2))
            message = .resize(cols: cols, rows: rows)
        default:
            message = .other(kind: f.kind, payload: f.payload)
        }
        if let r = routes[f.channel] {
            r.yield(message)
            if case .close = message {
                r.finish()
                routes[f.channel] = nil
            }
        } else {
            early[f.channel, default: []].append(message)
        }
    }

    private func handleRPC(_ line: Data) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: line) else { return }
        guard let idValue = json["id"], let id = idValue.int else { return }
        if switchAfter == id {
            switchAfter = nil
            if json["error"] == nil { framed = true }
        }
        guard let cont = pending.removeValue(forKey: id) else { return }
        if let err = json["error"], !err.isNull {
            cont.resume(throwing: RPCError(code: err["code"]?.int ?? -1, message: err["message"]?.string ?? "error", data: err["data"]))
        } else {
            cont.resume(returning: json["result"] ?? .null)
        }
    }
}
