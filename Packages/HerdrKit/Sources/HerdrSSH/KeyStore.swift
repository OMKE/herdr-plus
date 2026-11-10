import Foundation
import Crypto
import Security

public typealias Curve25519Key = Curve25519.Signing.PrivateKey

public enum KeyStore {
    static let service = "io.github.herdr-ios.ssh"
    static let account = "ed25519"

    public static func loadOrCreate() throws -> Curve25519.Signing.PrivateKey {
        if let k = load() { return k }
        let k = Curve25519.Signing.PrivateKey()
        try save(k)
        return k
    }

    public static func load() -> Curve25519.Signing.PrivateKey? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    public static func save(_ key: Curve25519.Signing.PrivateKey) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = key.rawRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public static func reset() throws -> Curve25519.Signing.PrivateKey {
        let k = Curve25519.Signing.PrivateKey()
        try save(k)
        return k
    }

    public static func openSSHPublicKey(_ key: Curve25519.Signing.PrivateKey, comment: String = "herdr-ios") -> String {
        var blob = Data()
        func put(_ d: Data) {
            var n = UInt32(d.count).bigEndian
            withUnsafeBytes(of: &n) { blob.append(contentsOf: $0) }
            blob.append(d)
        }
        put(Data("ssh-ed25519".utf8))
        put(key.publicKey.rawRepresentation)
        return "ssh-ed25519 " + blob.base64EncodedString() + " " + comment
    }
}
