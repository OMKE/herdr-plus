import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH
import HerdrKit

public enum SSHAuthMode: String, Sendable, Hashable, Codable, CaseIterable {
    case key
    case tailscale
}

public struct SSHTarget: Sendable, Hashable, Codable {
    public var host: String
    public var port: Int
    public var username: String
    public var command: String
    public var auth: SSHAuthMode

    public static let defaultCommand = "~/.local/bin/hc connect"

    public init(host: String, port: Int = 22, username: String, command: String = SSHTarget.defaultCommand, auth: SSHAuthMode = .key) {
        self.host = host
        self.port = port
        self.username = username
        self.command = command
        self.auth = auth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try c.decode(String.self, forKey: .username)
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? SSHTarget.defaultCommand
        auth = try c.decodeIfPresent(SSHAuthMode.self, forKey: .auth) ?? .key
    }

    func method(_ key: Curve25519.Signing.PrivateKey) -> SSHAuthenticationMethod {
        switch auth {
        case .key: .ed25519(username: username, privateKey: key)
        case .tailscale: .custom(NoneThenKey(username: username, key: key))
        }
    }
}

final class NoneThenKey: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let key: Curve25519.Signing.PrivateKey
    private var step = 0

    init(username: String, key: Curve25519.Signing.PrivateKey) {
        self.username = username
        self.key = key
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        defer { step += 1 }
        switch step {
        case 0:
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .none))
        case 1 where availableMethods.contains(.publicKey):
            nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .privateKey(.init(privateKey: NIOSSHPrivateKey(ed25519Key: key)))))
        default:
            nextChallengePromise.succeed(nil)
        }
    }
}

public enum HostKeyDecision: Sendable {
    case trusted
    case unknown(fingerprint: String)
    case mismatch(expected: String, got: String)
}

public enum SSHTransportError: Error, CustomStringConvertible, Sendable {
    case hostKeyUnknown(String)
    case hostKeyMismatch(expected: String, got: String)
    case exited(String)

    public var description: String {
        switch self {
        case .hostKeyUnknown(let f): "Unknown host key \(f)"
        case .hostKeyMismatch(let e, let g): "Host key changed. Expected \(e), got \(g)"
        case .exited(let s): s.isEmpty ? "Remote command exited" : s
        }
    }
}

public enum Fingerprint {
    public static func of(_ key: NIOSSHPublicKey) -> String {
        let line = String(openSSHPublicKey: key)
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else { return line }
        let digest = SHA256.hash(data: blob)
        let b64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:" + b64
    }
}

final class FingerprintValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let expected: String?
    private(set) var seen: String?

    init(expected: String?) {
        self.expected = expected
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fp = Fingerprint.of(hostKey)
        seen = fp
        guard let expected else {
            validationCompletePromise.fail(SSHTransportError.hostKeyUnknown(fp))
            return
        }
        if expected == fp {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(SSHTransportError.hostKeyMismatch(expected: expected, got: fp))
        }
    }
}

public enum SSHProbe {
    public static func hostFingerprint(host: String, port: Int = 22, username: String, key: Curve25519.Signing.PrivateKey) async throws -> String {
        let validator = FingerprintValidator(expected: nil)
        do {
            let client = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: .ed25519(username: username, privateKey: key),
                hostKeyValidator: .custom(validator),
                reconnect: .never,
                connectTimeout: .seconds(10)
            )
            try? await client.close()
        } catch {
            if let fp = validator.seen { return fp }
            throw error
        }
        if let fp = validator.seen { return fp }
        throw SSHTransportError.exited("No host key")
    }

    public static func run(_ target: SSHTarget, fingerprint: String, key: Curve25519.Signing.PrivateKey, command: String) async throws -> String {
        let client = try await SSHClient.connect(
            host: target.host,
            port: target.port,
            authenticationMethod: target.method(key),
            hostKeyValidator: .custom(FingerprintValidator(expected: fingerprint)),
            reconnect: .never,
            connectTimeout: .seconds(10)
        )
        defer { Task { try? await client.close() } }
        let out = try await client.executeCommand(command, mergeStreams: true)
        return String(buffer: out)
    }
}

public final class SSHTransport: ByteTransport, @unchecked Sendable {
    public let incoming: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let client: SSHClient
    private var writer: TTYStdinWriter?
    private var waiters: [CheckedContinuation<TTYStdinWriter, Error>] = []
    private var task: Task<Void, Never>?
    private let lock = NSLock()
    private var finished = false
    private var stderr = Data()

    public static func connect(_ target: SSHTarget, fingerprint: String, key: Curve25519.Signing.PrivateKey) async throws -> SSHTransport {
        let client = try await SSHClient.connect(
            host: target.host,
            port: target.port,
            authenticationMethod: target.method(key),
            hostKeyValidator: .custom(FingerprintValidator(expected: fingerprint)),
            reconnect: .never,
            connectTimeout: .seconds(10)
        )
        let t = SSHTransport(client: client)
        t.start(command: target.command)
        _ = try await t.waitWriter()
        return t
    }

    private init(client: SSHClient) {
        self.client = client
        (incoming, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    }

    private func start(command: String) {
        let cont = continuation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.withExec(command) { inbound, outbound in
                    self.setWriter(outbound)
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buf):
                            cont.yield(Data(buffer: buf))
                        case .stderr(let buf):
                            self.appendStderr(Data(buffer: buf))
                        }
                    }
                }
                self.finish(nil)
            } catch {
                self.finish(error)
            }
        }
    }

    private func appendStderr(_ d: Data) {
        lock.withLock {
            stderr.append(d)
            if stderr.count > 8192 { stderr = stderr.suffix(4096) }
        }
    }

    public var stderrText: String { lock.withLock { String(decoding: stderr, as: UTF8.self) } }

    private func setWriter(_ w: TTYStdinWriter) {
        let ws: [CheckedContinuation<TTYStdinWriter, Error>] = lock.withLock {
            writer = w
            let ws = waiters
            waiters = []
            return ws
        }
        for c in ws { c.resume(returning: w) }
    }

    private func finish(_ error: Error?) {
        let ws: [CheckedContinuation<TTYStdinWriter, Error>] = lock.withLock {
            finished = true
            let ws = waiters
            waiters = []
            return ws
        }
        let err = error ?? SSHTransportError.exited(stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
        for c in ws { c.resume(throwing: err) }
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }

    private func waitWriter() async throws -> TTYStdinWriter {
        try await withCheckedThrowingContinuation { c in
            let ready: TTYStdinWriter?? = lock.withLock {
                if let writer { return .some(writer) }
                if finished { return .some(nil) }
                waiters.append(c)
                return nil
            }
            switch ready {
            case .some(.some(let w)): c.resume(returning: w)
            case .some(.none): c.resume(throwing: SSHTransportError.exited(stderrText))
            case .none: break
            }
        }
    }

    public func send(_ data: Data) async throws {
        let w = try await waitWriter()
        try await w.write(ByteBuffer(bytes: data))
    }

    public func close() async {
        task?.cancel()
        try? await client.close()
        continuation.finish()
    }
}

extension Data {
    init(buffer: ByteBuffer) {
        var b = buffer
        self = b.readData(length: b.readableBytes) ?? Data()
    }
}
