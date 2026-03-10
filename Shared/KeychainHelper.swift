import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.juicebox.claudeusage"
    private static let sessionKeyAccount = "sessionKey"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionKeyAccount,
        ]
    }

    static func saveSessionKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        // Delete any existing item first
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainHelper] Save failed with OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func loadSessionKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status != errSecSuccess {
            print("[KeychainHelper] Load failed with OSStatus \(status)")
        }

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteSessionKey() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
