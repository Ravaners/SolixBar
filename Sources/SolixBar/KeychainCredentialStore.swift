import Foundation
import Security

struct SolixCredentials: Sendable, Equatable {
    var email: String
    var password: String

    var isComplete: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
}

enum KeychainCredentialStore {
    private static let service = "local.codex.SolixBar.solix"
    private static let account = "primary"

    static func load() -> SolixCredentials {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let credentials = try? JSONDecoder().decode(CodableCredentials.self, from: data) else {
            return SolixCredentials(email: "", password: "")
        }
        return SolixCredentials(email: credentials.email, password: credentials.password)
    }

    static func save(_ credentials: SolixCredentials) throws {
        if !credentials.isComplete {
            try delete()
            return
        }

        let data = try JSONEncoder().encode(
            CodableCredentials(email: credentials.email, password: credentials.password)
        )
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw KeychainError(status: insertStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct CodableCredentials: Codable {
    var email: String
    var password: String
}

private struct KeychainError: LocalizedError {
    var status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unbekannter Keychain-Fehler"
        return "Keychain: \(message) (\(status))"
    }
}
