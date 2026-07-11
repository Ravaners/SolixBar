import Foundation
import Security

/// Speichert das SOLIX-Passwort im macOS-Schlüsselbund statt im Klartext.
enum KeychainStore {
    private static let service = "local.codex.SolixBar"

    static func setPassword(_ password: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8)
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = Data(password.utf8)
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    static func password(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let code):
                "Schlüsselbund-Fehler \(code)."
            }
        }
    }
}
