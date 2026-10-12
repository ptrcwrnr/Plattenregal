import Foundation
import Security

nonisolated enum KeychainStore {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "de.private.Plattenregal.discogs", kSecAttrAccount as String: "personal-token"] }
    /// Demo launches use sample data and must never read – or overwrite – the real token.
    private static var isDemo: Bool { DemoMode.isActive }
    /// A non-empty token is stored. An unreadable keychain counts as yes: the
    /// sync then reports the actual problem.
    static var hasToken: Bool {
        // The demo never touches the keychain.
        if isDemo { return true }
        // Unreadable: offer the sync, which then says what's wrong.
        do { return !(try load() ?? "").isEmpty } catch {
            AppLog.warning("Discogs", "Schlüsselbund nicht lesbar, Token wird als vorhanden angenommen: \(error)")
            return true
        }
    }

    static func load() throws -> String? {
        if isDemo { return nil }
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }
    static func store(_ token: String) throws {
        if isDemo { return }
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
nonisolated struct KeychainError: LocalizedError {
    let status: OSStatus
    // The status remains part of the error for the technical protocol.
    var errorDescription: String? { String(localized: "Plattenregal kommt gerade nicht an den Schlüsselbund von macOS, in dem der Discogs-Token liegt. Erlaube den Zugriff, falls macOS danach fragt, und versuche es noch einmal.") }
}
