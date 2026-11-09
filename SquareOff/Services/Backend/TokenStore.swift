import Foundation
import Security
import SquareOffNet

/// Where the session token lives. The live backend keeps it in the Keychain; the mock in
/// UserDefaults (it is just `mock:<username>`); tests in memory.
nonisolated protocol TokenStore: TokenProvider {
    func store(_ token: String) throws
    func clear()
}

nonisolated final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func accessToken() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func store(_ token: String) throws {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }

    struct KeychainError: Error { let status: OSStatus }
}

nonisolated final class UserDefaultsTokenStore: TokenStore, @unchecked Sendable {
    private let key: String
    private let defaults: UserDefaults

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func accessToken() -> String? { defaults.string(forKey: key) }
    func store(_ token: String) throws { defaults.set(token, forKey: key) }
    func clear() { defaults.removeObject(forKey: key) }
}

nonisolated final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) { self.token = token }

    func accessToken() -> String? { lock.withLock { token } }
    func store(_ token: String) throws { lock.withLock { self.token = token } }
    func clear() { lock.withLock { token = nil } }
}

/// Just enough JWT parsing to skip a network round-trip for a token that has already expired.
nonisolated enum JWT {
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func isExpired(_ token: String, now: Date = Date()) -> Bool {
        guard let expiry = expiry(of: token) else { return false }
        return expiry <= now
    }
}
