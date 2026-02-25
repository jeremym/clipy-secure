import Foundation
import Security

final class EncryptionKeyManager: Sendable {
    private static let service = "com.clipysecure.dbkey"
    private static let account = "database-encryption-key"
    private static let keyLength = 32

    func getOrCreateDatabaseKey() throws -> String {
        if let existingKey = try readKeyFromKeychain() {
            return existingKey
        }
        let newKey = generateRandomKey()
        try storeKeyInKeychain(newKey)
        return newKey
    }

    private func generateRandomKey() -> String {
        var bytes = [UInt8](repeating: 0, count: Self.keyLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, Self.keyLength, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func readKeyFromKeychain() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw EncryptionKeyError.corruptedKey
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw EncryptionKeyError.keychainError(status)
        }
    }

    private func storeKeyInKeychain(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw EncryptionKeyError.corruptedKey
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionKeyError.keychainError(status)
        }
    }
}

enum EncryptionKeyError: Error, LocalizedError {
    case corruptedKey
    case keychainError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .corruptedKey:
            return "The encryption key in the Keychain is corrupted."
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
