import Foundation
import Security

enum KeychainStore {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "de.private.Plattenregal.discogs", kSecAttrAccount as String: "personal-token"] }
    static func load() throws -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }
    static func store(_ token: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var q = query; q.merge(attributes) { _, new in new }
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(q as CFDictionary, nil)
        if added == errSecSuccess { return }
        if added == errSecDuplicateItem {
            // Lost a race with a concurrent store() that added the item first; update it instead.
            let retry = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retry == errSecSuccess else { throw KeychainError(status: retry) }
            return
        }
        throw KeychainError(status: added)
    }
}
struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Der Schlüsselbund ist nicht verfügbar (\(status)). Bitte prüfe den Zugriff in macOS." }
}
