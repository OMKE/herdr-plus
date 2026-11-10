import Foundation
import Network
import Darwin

struct FoundMac: Identifiable, Hashable {
    var name: String
    var short = ""
    var host: String
    var address: String?
    var viaTailscale: Bool
    var id: String { name }
}

enum TailnetProbe {
    static func isTailnet(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        return p.count == 4 && p[0] == 100 && (64...127).contains(p[1])
    }

    static func ownAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            defer { cur = p.pointee.ifa_next }
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: buf)
                if isTailnet(ip) { return ip }
            }
        }
        return nil
    }

    static func resolve(_ host: String) async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { cont.resume(returning: []); return }
                defer { freeaddrinfo(res) }
                var out: [String] = []
                var cur: UnsafeMutablePointer<addrinfo>? = first
                while let p = cur {
                    if let sa = p.pointee.ai_addr {
                        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sa, p.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                            out.append(String(cString: buf))
                        }
                    }
                    cur = p.pointee.ai_next
                }
                cont.resume(returning: out)
            }
        }
    }

    static func magicSuffix(ownIP: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var sin = sockaddr_in()
                sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                sin.sin_family = sa_family_t(AF_INET)
                guard inet_pton(AF_INET, ownIP, &sin.sin_addr) == 1 else { cont.resume(returning: nil); return }
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = withUnsafePointer(to: &sin) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buf, socklen_t(buf.count), nil, 0, NI_NAMEREQD)
                    }
                }
                guard rc == 0 else { cont.resume(returning: nil); return }
                var name = String(cString: buf)
                if name.hasSuffix(".") { name.removeLast() }
                let parts = name.split(separator: ".")
                guard parts.count > 2, name.hasSuffix(".ts.net") else { cont.resume(returning: nil); return }
                cont.resume(returning: parts.dropFirst().joined(separator: "."))
            }
        }
    }

    static func machineName(_ computerName: String) -> String {
        let folded = computerName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var out = ""
        var dash = false
        for ch in folded {
            if ch == "'" || ch == "’" { continue }
            if ch.isASCII, ch.isLetter || ch.isNumber {
                out.append(ch)
                dash = false
            } else if !dash, !out.isEmpty {
                out.append("-")
                dash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.lowercased()
    }
}

enum MagicDNS {
    static func query(_ name: String, type: UInt16) -> Data {
        var d = Data([UInt8.random(in: 0...255), UInt8.random(in: 0...255), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0])
        for label in name.split(separator: ".") {
            let b = Array(label.utf8.prefix(63))
            d.append(UInt8(b.count))
            d.append(contentsOf: b)
        }
        d.append(contentsOf: [0, UInt8(type >> 8), UInt8(type & 0xff), 0, 1])
        return d
    }

    static func readName(_ b: [UInt8], _ start: Int) -> (String, Int)? {
        var labels: [String] = []
        var i = start
        var end: Int?
        var jumps = 0
        while i < b.count {
            let len = Int(b[i])
            if len == 0 { return (labels.joined(separator: "."), end ?? i + 1) }
            if len & 0xc0 == 0xc0 {
                guard i + 1 < b.count, jumps < 16 else { return nil }
                if end == nil { end = i + 2 }
                i = (len & 0x3f) << 8 | Int(b[i + 1])
                jumps += 1
                continue
            }
            guard i + 1 + len <= b.count else { return nil }
            labels.append(String(decoding: b[(i + 1)..<(i + 1 + len)], as: UTF8.self))
            i += 1 + len
        }
        return nil
    }

    static func answers(_ data: Data, type: UInt16) -> [String] {
        let b = [UInt8](data)
        guard b.count >= 12 else { return [] }
        let qd = Int(b[4]) << 8 | Int(b[5])
        let an = Int(b[6]) << 8 | Int(b[7])
        var i = 12
        for _ in 0..<qd {
            guard let (_, next) = readName(b, i) else { return [] }
            i = next + 4
        }
        var out: [String] = []
        for _ in 0..<an {
            guard let (_, next) = readName(b, i), next + 10 <= b.count else { break }
            let t = UInt16(b[next]) << 8 | UInt16(b[next + 1])
            let len = Int(b[next + 8]) << 8 | Int(b[next + 9])
            let rd = next + 10
            guard rd + len <= b.count else { break }
            if t == type {
                if type == 1, len == 4 { out.append(b[rd..<rd + 4].map(String.init).joined(separator: ".")) }
                if type == 12, let (n, _) = readName(b, rd) { out.append(n) }
            }
            i = rd + len
        }
        return out
    }

    static func ask(_ name: String, type: UInt16, timeout: Double = 2) async -> [String] {
        let conn = NWConnection(host: "100.100.100.100", port: 53, using: .udp)
        return await withCheckedContinuation { cont in
            let done = OnceFlag()
            let finish: ([String]) -> Void = { r in if done.set() { conn.cancel(); cont.resume(returning: r) } }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: query(name, type: type), completion: .contentProcessed { err in if err != nil { finish([]) } })
                    conn.receiveMessage { data, _, _, _ in finish(data.map { answers($0, type: type) } ?? []) }
                case .failed, .cancelled: finish([])
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish([]) }
        }
    }

    static func ptrName(_ ip: String) -> String {
        ip.split(separator: ".").reversed().joined(separator: ".") + ".in-addr.arpa"
    }
}

@MainActor
final class ServiceResolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private var cont: CheckedContinuation<String?, Never>?
    private static var live: Set<ServiceResolver> = []

    private init(name: String, type: String) {
        service = NetService(domain: "local.", type: type, name: name)
    }

    static func host(name: String, type: String) async -> String? {
        let r = ServiceResolver(name: name, type: type)
        live.insert(r)
        defer { live.remove(r) }
        return await withCheckedContinuation { c in
            r.cont = c
            r.service.delegate = r
            r.service.resolve(withTimeout: 5)
        }
    }

    private func finish(_ host: String?) {
        cont?.resume(returning: host)
        cont = nil
        service.stop()
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let h = sender.hostName
        MainActor.assumeIsolated { finish(h) }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        MainActor.assumeIsolated { finish(nil) }
    }
}

@MainActor
@Observable
final class MacDiscovery {
    var found: [FoundMac] = []
    var searching = false
    var tailnetIP: String?
    var denied = false

    @ObservationIgnored private var browsers: [NWBrowser] = []
    @ObservationIgnored private var resolving: Set<String> = []
    @ObservationIgnored private var types: [String: String] = [:]
    @ObservationIgnored private var suffix: String?

    func start() {
        stop()
        tailnetIP = TailnetProbe.ownAddress()
        searching = true
        denied = false
        for type in ["_ssh._tcp", "_sftp-ssh._tcp"] {
            let params = NWParameters()
            params.includePeerToPeer = false
            let b = NWBrowser(for: .bonjour(type: type, domain: "local."), using: params)
            b.browseResultsChangedHandler = { [weak self] results, _ in
                let names = results.compactMap { r -> String? in
                    if case .service(let name, _, _, _) = r.endpoint { return name }
                    return nil
                }
                Task { @MainActor in
                    for n in names where self?.types[n] == nil { self?.types[n] = type + "." }
                    self?.add(names)
                }
            }
            b.stateUpdateHandler = { [weak self] state in
                if case .failed = state { Task { @MainActor in self?.searching = false } }
                if case .waiting(let err) = state, case .dns(let code) = err, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
                    Task { @MainActor in self?.denied = true }
                }
            }
            b.start(queue: .main)
            browsers.append(b)
        }
        Task {
            try? await Task.sleep(for: .seconds(8))
            searching = false
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        searching = false
    }

    private func add(_ names: [String]) {
        for n in names where !resolving.contains(n) && !found.contains(where: { $0.name == n }) {
            resolving.insert(n)
            Task { await resolve(n) }
        }
    }

    private func resolve(_ name: String) async {
        let bonjourHost = await ServiceResolver.host(name: name, type: types[name] ?? "_ssh._tcp.")
        let local = bonjourHost.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 } ?? TailnetProbe.machineName(name) + ".local"
        let short = (local.hasSuffix(".local") ? String(local.dropLast(6)) : local).lowercased()
        var mac = FoundMac(name: name, short: short, host: local, address: nil, viaTailscale: false)
        if suffix == nil, let ip = tailnetIP {
            if let ptr = await MagicDNS.ask(MagicDNS.ptrName(ip), type: 12).first, ptr.hasSuffix(".ts.net") {
                suffix = ptr.split(separator: ".").dropFirst().joined(separator: ".")
            } else {
                suffix = await TailnetProbe.magicSuffix(ownIP: ip)
            }
        }
        var candidates = [short]
        if let suffix { candidates.insert(short + "." + suffix, at: 0) }
        for c in candidates where !short.isEmpty {
            var ips = await MagicDNS.ask(c, type: 1)
            if ips.isEmpty { ips = await TailnetProbe.resolve(c) }
            if let ip = ips.first(where: TailnetProbe.isTailnet) {
                let systemSees = await TailnetProbe.resolve(c).contains(ip)
                mac.host = systemSees ? c : ip
                mac.address = ip
                mac.viaTailscale = true
                break
            }
        }
        if !mac.viaTailscale, let ip = await TailnetProbe.resolve(local).first {
            mac.address = ip
        }
        if !found.contains(where: { $0.name == name }) {
            found.append(mac)
            found.sort { ($0.viaTailscale ? 0 : 1, $0.name) < ($1.viaTailscale ? 0 : 1, $1.name) }
        }
        resolving.remove(name)
    }
}
