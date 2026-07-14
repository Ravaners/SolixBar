import CryptoKit
import Foundation

struct SolixCredentials: Sendable, Equatable {
    var email: String
    var password: String

    var isComplete: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
}

enum EncryptedCredentialStore {
    private static let authenticatedData = Data("local.codex.SolixBar.credentials.v1".utf8)
    private static var fileManager: FileManager { FileManager() }

    static func load() -> SolixCredentials {
        do {
            guard fileManager.fileExists(atPath: credentialsURL.path),
                  let key = try encryptionKey(createIfMissing: false) else {
                return emptyCredentials
            }

            let encryptedData = try Data(contentsOf: credentialsURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let clearData = try AES.GCM.open(
                sealedBox,
                using: key,
                authenticating: authenticatedData
            )
            let stored = try JSONDecoder().decode(CodableCredentials.self, from: clearData)
            return SolixCredentials(email: stored.email, password: stored.password)
        } catch {
            AppLogger.info("Encrypted credentials could not be loaded: \(error.localizedDescription)")
            return emptyCredentials
        }
    }

    static func save(_ credentials: SolixCredentials) throws {
        guard credentials.isComplete else {
            try delete()
            return
        }

        let key = try encryptionKey(createIfMissing: true)!
        let clearData = try JSONEncoder().encode(
            CodableCredentials(email: credentials.email, password: credentials.password)
        )
        let sealedBox = try AES.GCM.seal(
            clearData,
            using: key,
            authenticating: authenticatedData
        )
        guard let encryptedData = sealedBox.combined else {
            throw CredentialStoreError.encryptionFailed
        }
        try writePrivate(encryptedData, to: credentialsURL)
    }

    static func delete() throws {
        guard fileManager.fileExists(atPath: credentialsURL.path) else { return }
        try fileManager.removeItem(at: credentialsURL)
    }

    private static func encryptionKey(createIfMissing: Bool) throws -> SymmetricKey? {
        if fileManager.fileExists(atPath: keyURL.path) {
            let keyData = try Data(contentsOf: keyURL)
            guard keyData.count == 32 else { throw CredentialStoreError.invalidKey }
            return SymmetricKey(data: keyData)
        }
        guard createIfMissing else { return nil }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try writePrivate(keyData, to: keyURL)
        return key
    }

    private static func writePrivate(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDirectory.path)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static var supportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SolixBar", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SolixBar", isDirectory: true)
    }

    private static var credentialsURL: URL {
        supportDirectory.appendingPathComponent("credentials.enc")
    }

    private static var keyURL: URL {
        supportDirectory.appendingPathComponent("credentials.key")
    }

    private static var emptyCredentials: SolixCredentials {
        SolixCredentials(email: "", password: "")
    }
}

private struct CodableCredentials: Codable {
    var email: String
    var password: String
}

private enum CredentialStoreError: LocalizedError {
    case encryptionFailed
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            "Die Zugangsdaten konnten nicht verschlüsselt werden."
        case .invalidKey:
            "Der lokale Schlüssel für die Zugangsdaten ist ungültig."
        }
    }
}
