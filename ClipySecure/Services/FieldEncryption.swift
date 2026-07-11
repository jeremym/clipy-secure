import CryptoKit
import Foundation

/// AES-GCM field-level encryption for sensitive clipboard content.
/// The master key comes from the Keychain-stored database key; separate
/// subkeys for encryption and hashing are derived with HKDF so the same
/// key material is never used by two primitives.
final class FieldEncryption: Sendable {
    private let encryptionKey: SymmetricKey
    private let hashKey: SymmetricKey

    init(key masterKey: SymmetricKey) {
        self.encryptionKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: Data("com.clipysecure.field-encryption".utf8),
            outputByteCount: 32
        )
        self.hashKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: Data("com.clipysecure.content-hash".utf8),
            outputByteCount: 32
        )
    }

    convenience init(keyManager: EncryptionKeyManager) throws {
        let base64Key = try keyManager.getOrCreateDatabaseKey()
        guard let keyData = Data(base64Encoded: base64Key) else {
            throw EncryptionKeyError.corruptedKey
        }
        self.init(key: SymmetricKey(data: keyData))
    }

    /// A random single-session key that never touches the Keychain.
    /// Used by in-memory test databases.
    static func ephemeral() -> FieldEncryption {
        FieldEncryption(key: SymmetricKey(size: .bits256))
    }

    // MARK: - String

    func encrypt(_ plaintext: String) throws -> Data {
        try encrypt(Data(plaintext.utf8))
    }

    func decryptString(_ ciphertext: Data) throws -> String {
        let plainData = try decryptData(ciphertext)
        guard let string = String(data: plainData, encoding: .utf8) else {
            throw FieldEncryptionError.decodingFailure
        }
        return string
    }

    // MARK: - Data (blobs)

    func encrypt(_ plainData: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plainData, using: encryptionKey)
        guard let combined = sealed.combined else {
            throw FieldEncryptionError.sealFailure
        }
        return combined
    }

    func decryptData(_ ciphertext: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: encryptionKey)
    }

    // MARK: - Keyed hashing

    /// HMAC-SHA256 over a content hash, hex-encoded. Stored in place of the
    /// plain SHA-256 so the database file cannot be used to confirm or crack
    /// clipboard content (e.g. dictionary attacks against short secrets).
    func keyedHash(_ contentHash: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(contentHash.utf8), using: hashKey)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

enum FieldEncryptionError: Error, LocalizedError {
    case sealFailure
    case decodingFailure

    var errorDescription: String? {
        switch self {
        case .sealFailure:
            return "Failed to encrypt data."
        case .decodingFailure:
            return "Failed to decode decrypted data."
        }
    }
}
