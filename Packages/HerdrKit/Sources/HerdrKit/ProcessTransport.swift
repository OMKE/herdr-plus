#if os(macOS)
import Foundation

public final class ProcessTransport: ByteTransport, @unchecked Sendable {
    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    public let incoming: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()

    public init(executable: String, arguments: [String], environment: [String: String]? = nil) throws {
        (incoming, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let cont = continuation
        stdout.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty {
                h.readabilityHandler = nil
                cont.finish()
            } else {
                cont.yield(d)
            }
        }
        process.terminationHandler = { _ in cont.finish() }
        try process.run()
    }

    public func send(_ data: Data) async throws {
        try lock.withLock {
            try stdin.fileHandleForWriting.write(contentsOf: data)
        }
    }

    public func close() async {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        continuation.finish()
    }
}
#endif
