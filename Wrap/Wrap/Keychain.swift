import Foundation
import Security

/// Stores small secrets (like the login session) in the macOS Keychain.
enum Keychain {
    private static let service = "com.xanzplug.Wrap"

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func save(_ value: String, for key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
        var query = baseQuery(key)
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
