import Foundation
import Security

/// Thin wrapper around the macOS Keychain for reading the AI API key.
/// The key is only ever read at call time, never cached in memory
/// longer than needed, and never written to disk or logs.
struct KeychainStore: Sendable {
    let service: String
    let account: String

    init(service: String = Constants.AIAssist.keychainService,
         account: String = Constants.AIAssist.keychainAccount) {
        self.service = service
        self.account = account
    }

    func readAPIKey() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
