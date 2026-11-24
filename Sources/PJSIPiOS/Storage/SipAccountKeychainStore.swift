import Foundation
import Security

/// Encrypted credential storage backed by the iOS Keychain,
/// mirroring VoiSmart/pjsip-android's Jetpack Security encrypted account store.
public final class SipAccountKeychainStore: Sendable {
    private let service: String
    private let accessGroup: String?

    public init(service: String = "com.pjsipios.accounts", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func save(_ account: SipAccountConfiguration) throws {
        try account.validate()
        let data = try JSONEncoder().encode(account)
        let key = account.idURI

        var query = baseQuery(accountKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SipError.keychainFailure(addStatus)
            }
            return
        }
        throw SipError.keychainFailure(updateStatus)
    }

    public func load(accountIdURI: String) throws -> SipAccountConfiguration? {
        var query = baseQuery(accountKey: accountIdURI)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SipError.keychainFailure(status)
        }
        return try JSONDecoder().decode(SipAccountConfiguration.self, from: data)
    }

    public func loadAll() throws -> [SipAccountConfiguration] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess, let items = result as? [Data] else {
            throw SipError.keychainFailure(status)
        }
        let decoder = JSONDecoder()
        return try items.map { try decoder.decode(SipAccountConfiguration.self, from: $0) }
    }

    public func delete(accountIdURI: String) throws {
        let query = baseQuery(accountKey: accountIdURI)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SipError.keychainFailure(status)
        }
    }

    public func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SipError.keychainFailure(status)
        }
    }

    private func baseQuery(accountKey: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
