import Foundation
import Security

/// Passwords for the configured boxes.
///
/// These are *this app's* keychain items. The entries the Finder created when the volumes were
/// mounted live in the login keychain and belong to another application, and the sandbox keeps
/// them out of reach — so each box's password is entered once here and stored separately.
enum KeychainStore {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return String(
                    localized: "Schlüsselbund-Fehler: \(message ?? "Status \(status)")"
                )
            }
        }
    }

    private static func query(host: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: account,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
        ]
    }

    static func password(host: String, account: String) throws -> String? {
        var query = query(host: host, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Upsert — `SecItemAdd` reports `errSecDuplicateItem` rather than replacing, so an
    /// existing entry is updated in place.
    static func setPassword(_ password: String, host: String, account: String) throws {
        let data = Data(password.utf8)
        let query = query(host: host, account: account)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrLabel as String] = "Storage Boxes — \(host)"
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(attributes as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update = [kSecValueData as String: data] as CFDictionary
            let updateStatus = SecItemUpdate(query as CFDictionary, update)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func deletePassword(host: String, account: String) throws {
        let status = SecItemDelete(query(host: host, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
