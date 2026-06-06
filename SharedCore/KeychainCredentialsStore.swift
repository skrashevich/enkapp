import Foundation
import Security

enum KeychainCredentialsStore {
    private static let service = "dev.encx-cli.credentials"

    enum Error: Swift.Error {
        case encodingFailed
        case unhandled(OSStatus)
    }

    static func accountKey(domain: String, login: String) -> String {
        "\(login.lowercased())@\(domain.lowercased())"
    }

    static func save(password: String, domain: String, login: String) throws {
        let account = accountKey(domain: domain, login: login)
        guard let data = password.data(using: .utf8) else {
            throw Error.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else { throw Error.unhandled(updateStatus) }
        } else if status != errSecSuccess {
            throw Error.unhandled(status)
        }
    }

    static func loadPassword(domain: String, login: String) -> String? {
        let account = accountKey(domain: domain, login: login)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        return password
    }

    static func delete(domain: String, login: String) {
        let account = accountKey(domain: domain, login: login)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
