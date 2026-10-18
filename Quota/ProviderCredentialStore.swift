import Foundation
import Security

enum ProviderCredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "无法访问钥匙串（错误码 \(status)）。"
        }
    }
}

enum ProviderCredentialStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.ceaser.Quota"
    private static let legacyAccount = "deepseek-api-key"

    static func read(provider: ProviderID, field: ProviderFieldKey) -> String? {
        read(account: account(provider: provider, field: field))
    }

    static func save(_ value: String, provider: ProviderID, field: ProviderFieldKey) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = account(provider: provider, field: field)

        guard !trimmed.isEmpty else {
            try delete(account: account)
            return
        }

        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insertQuery = query
            attributes.forEach { insertQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                throw ProviderCredentialStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw ProviderCredentialStoreError.keychain(updateStatus)
        }
    }

    static func deleteAll(provider: ProviderID) {
        accountKeys(for: provider).forEach { account in
            try? delete(account: account)
        }
    }

    static func mask(_ value: String) -> String {
        guard value.count > 10 else {
            return "••••••••"
        }

        return "\(value.prefix(6))••••\(value.suffix(4))"
    }

    static func migrateLegacyDeepSeekKeyIfNeeded() -> Bool {
        guard read(provider: .deepseek, field: .apiKey) == nil,
              let legacyKey = read(account: legacyAccount),
              !legacyKey.isEmpty else {
            return false
        }

        try? save(legacyKey, provider: .deepseek, field: .apiKey)
        return true
    }

    private static func account(provider: ProviderID, field: ProviderFieldKey) -> String {
        "\(provider.rawValue).\(field.rawValue)"
    }

    private static func accountKeys(for provider: ProviderID) -> [String] {
        [
            account(provider: provider, field: .apiKey),
            account(provider: provider, field: .managementKey),
            account(provider: provider, field: .teamID),
            account(provider: provider, field: .adminKey)
        ]
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProviderCredentialStoreError.keychain(status)
        }
    }
}
