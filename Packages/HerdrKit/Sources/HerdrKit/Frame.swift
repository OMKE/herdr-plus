import Foundation

public enum FrameKind: UInt8, Sendable {
    case data = 0
    case credit = 1
    case close = 2
    case resize = 3
    case focus = 4
    case facts = 5
    case automaticInput = 6
}

public struct Frame: Sendable, Equatable {
    public var channel: UInt32
    public var kind: UInt8
    public var payload: Data

    public init(channel: UInt32, kind: FrameKind, payload: Data) {
        self.channel = channel
        self.kind = kind.rawValue
        self.payload = payload
    }

    public init(channel: UInt32, rawKind: UInt8, payload: Data) {
        self.channel = channel
        self.kind = rawKind
        self.payload = payload
    }

    public var frameKind: FrameKind? { FrameKind(rawValue: kind) }

    public func encoded() -> Data {
        var out = Data(capacity: 9 + payload.count)
        out.appendLE(channel)
        out.append(kind)
        out.appendLE(UInt32(payload.count))
        out.append(payload)
        return out
    }

    public static func credit(channel: UInt32, bytes: UInt32) -> Frame {
        var p = Data()
        p.appendLE(bytes)
        return Frame(channel: channel, kind: .credit, payload: p)
    }

    public static func resize(channel: UInt32, cols: UInt16, rows: UInt16) -> Frame {
        var p = Data()
        p.appendLE(cols)
        p.appendLE(rows)
        return Frame(channel: channel, kind: .resize, payload: p)
    }

    public static func focus(channel: UInt32, focused: Bool) -> Frame {
        Frame(channel: channel, kind: .focus, payload: Data([focused ? 1 : 0]))
    }
}

public enum FrameError: Error, Equatable {
    case tooLarge(Int)
}

public struct FrameDecoder: Sendable {
    public static let maxPayload = 16 * 1024 * 1024
    private var buffer = Data()

    public init() {}

    public mutating func push(_ data: Data) throws -> [Frame] {
        buffer.append(data)
        var frames: [Frame] = []
        while buffer.count >= 9 {
            let start = buffer.startIndex
            let channel = buffer.readLE(UInt32.self, at: start)
            let kind = buffer[start + 4]
            let length = Int(buffer.readLE(UInt32.self, at: start + 5))
            if length > Self.maxPayload { throw FrameError.tooLarge(length) }
            guard buffer.count >= 9 + length else { break }
            let payload = Data(buffer[(start + 9)..<(start + 9 + length)])
            frames.append(Frame(channel: channel, rawKind: kind, payload: payload))
            buffer = Data(buffer[(start + 9 + length)...])
        }
        return frames
    }
}

public struct LineDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func push(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer = Data(buffer[(nl + 1)...])
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    public mutating func takeRemainder() -> Data {
        let rest = buffer
        buffer = Data()
        return rest
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_ type: T.Type, at index: Index) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value |= T(self[index + i]) << (8 * i)
        }
        return value
    }
}
