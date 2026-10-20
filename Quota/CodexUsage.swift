import Foundation
import Security

struct CodexDeviceCode: Equatable {
    let userCode: String
    let verificationURL: URL
    fileprivate let deviceAuthID: String
    fileprivate let pollInterval: Int
}

struct CodexUsageWindow: Identifiable {
    let id: String
    let title: String
    let usedPercent: Double?
    let resetAt: Date?

    var remainingPercent: Double? {
        guard let usedPercent else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }
}

struct CodexUsageSnapshot {
    let planType: String?
    let windows: [CodexUsageWindow]
    let resetCreditsAvailable: Int?
    let updatedAt: Date
}

struct CodexAccountInfo: Identifiable, Equatable {
    let id: String
    let displayName: String
    let email: String?
    let accountIDSuffix: String

    fileprivate init(credentials: CodexOAuthCredentials) {
        id = credentials.identityKey
        let name = credentials.resolvedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = credentials.resolvedEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = (name?.isEmpty == false ? name : nil)
            ?? (email?.isEmpty == false ? email : nil)
            ?? "ChatGPT 账号"
        self.email = email?.isEmpty == false ? email : nil
        accountIDSuffix = String(credentials.accountID.suffix(6))
    }

    var detail: String {
        if let email, email.caseInsensitiveCompare(displayName) != .orderedSame {
            return email
        }
        return "账号 ID · …\(accountIDSuffix)"
    }
}

enum CodexUsageError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case unauthorized
    case missingAccountID
    case deviceCodeUnavailable
    case deviceCodeExpired
    case noUsageWindows

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Codex 返回的数据格式无法识别。"
        case .httpStatus(let status):
            return "Codex 请求失败（状态码：\(status)）。"
        case .unauthorized:
            return "Codex 登录已过期，请重新登录。"
        case .missingAccountID:
            return "登录结果中没有 ChatGPT 账号标识，无法查询额度。"
        case .deviceCodeUnavailable:
            return "Codex device-code 登录暂不可用。请检查账号是否允许这种登录方式。"
        case .deviceCodeExpired:
            return "设备验证码已过期，请重新开始登录。"
        case .noUsageWindows:
            return "Codex 暂时没有返回额度窗口。"
        }
    }
}

@MainActor
final class CodexUsageStore: ObservableObject {
    @Published private(set) var accounts: [CodexAccountInfo]
    @Published private(set) var enabledAccountIDs: Set<String>
    @Published private(set) var isLoggingIn = false
    @Published private(set) var loadingAccountIDs: Set<String> = []
    @Published private(set) var deviceCode: CodexDeviceCode?
    @Published private(set) var snapshots: [String: CodexUsageSnapshot] = [:]
    @Published private(set) var accountErrors: [String: String] = [:]
    @Published private(set) var errorMessage: String?

    var isAuthenticated: Bool { !accounts.isEmpty }
    var isEnabled: Bool { !enabledAccountIDs.isEmpty }
    var enabledAccounts: [CodexAccountInfo] {
        accounts.filter { enabledAccountIDs.contains($0.id) }
    }
    var isLoading: Bool { !loadingAccountIDs.isEmpty }

    private let client = CodexUsageClient()
    private let defaults = UserDefaults.standard
    private let enabledAccountsKey = "codexUsageEnabledAccounts.v1"
    private let legacyEnabledKey = "codexUsageEnabled.v1"
    private var loginTask: Task<Void, Never>?

    init() {
        let credentials = CodexOAuthCredentialStore.loadAll()
        accounts = credentials.map(CodexAccountInfo.init)
        let defaults = UserDefaults.standard
        if let savedIDs = defaults.stringArray(forKey: "codexUsageEnabledAccounts.v1") {
            let accountIDs = Set(credentials.map(\.identityKey))
            enabledAccountIDs = Set(savedIDs).intersection(accountIDs)
        } else if defaults.bool(forKey: "codexUsageEnabled.v1") {
            // Migrate the former global switch by applying it to every saved account.
            enabledAccountIDs = Set(credentials.map(\.identityKey))
        } else {
            enabledAccountIDs = []
        }
        defaults.set(enabledAccountIDs.sorted(), forKey: "codexUsageEnabledAccounts.v1")
    }

    func isEnabled(accountID: String) -> Bool {
        enabledAccountIDs.contains(accountID)
    }

    func setEnabled(_ enabled: Bool, for accountID: String) {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        if enabled {
            enabledAccountIDs.insert(accountID)
            persistEnabledAccounts()
            Task { await refresh(accountID: accountID) }
        } else {
            enabledAccountIDs.remove(accountID)
            persistEnabledAccounts()
            snapshots[accountID] = nil
            accountErrors[accountID] = nil
            errorMessage = nil
        }
    }

    private func persistEnabledAccounts() {
        defaults.set(enabledAccountIDs.sorted(), forKey: enabledAccountsKey)
        defaults.set(isEnabled, forKey: legacyEnabledKey)
    }

    func beginLogin() {
        guard !isLoggingIn else { return }
        errorMessage = nil
        isLoggingIn = true
        deviceCode = nil

        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let flow = try await client.requestDeviceCode()
                guard !Task.isCancelled else { return }
                deviceCode = flow

                let credentials = try await client.completeDeviceCodeLogin(flow)
                guard !Task.isCancelled else { return }
                try CodexOAuthCredentialStore.save(credentials)
                reloadAccounts()
                enabledAccountIDs.insert(credentials.identityKey)
                persistEnabledAccounts()
                deviceCode = nil
                isLoggingIn = false
                loginTask = nil
                await refresh(accountID: credentials.identityKey)
            } catch is CancellationError {
                deviceCode = nil
                isLoggingIn = false
                loginTask = nil
            } catch {
                errorMessage = error.localizedDescription
                deviceCode = nil
                isLoggingIn = false
                loginTask = nil
            }
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        deviceCode = nil
        isLoggingIn = false
    }

    func signOut(accountID: String) {
        do {
            try CodexOAuthCredentialStore.delete(identityKey: accountID)
            enabledAccountIDs.remove(accountID)
            persistEnabledAccounts()
            snapshots[accountID] = nil
            accountErrors[accountID] = nil
            errorMessage = nil
            reloadAccounts()
        } catch {
            reloadAccounts()
            errorMessage = "退出账号失败：\(error.localizedDescription)"
        }
    }

    func signOut() {
        cancelLogin()
        do {
            try CodexOAuthCredentialStore.deleteAll()
            accounts = []
            enabledAccountIDs = []
            persistEnabledAccounts()
            snapshots = [:]
            accountErrors = [:]
            errorMessage = nil
        } catch {
            reloadAccounts()
            errorMessage = "退出账号失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func refreshAll() async -> Bool {
        let accountsToRefresh = enabledAccounts
        guard !accountsToRefresh.isEmpty else { return false }
        var succeeded = true
        for account in accountsToRefresh {
            let didSucceed = await refresh(accountID: account.id)
            if !didSucceed {
                succeeded = false
            }
        }
        return succeeded
    }

    @discardableResult
    func refresh(accountID: String) async -> Bool {
        guard isEnabled(accountID: accountID) else { return false }
        if loadingAccountIDs.contains(accountID) { return true }
        guard let credentials = CodexOAuthCredentialStore.loadAll()
            .first(where: { $0.identityKey == accountID }) else { return false }

        loadingAccountIDs.insert(accountID)
        accountErrors[accountID] = nil
        errorMessage = nil
        defer { loadingAccountIDs.remove(accountID) }

        do {
            let result = try await client.fetchUsage(using: credentials)
            guard isEnabled(accountID: accountID), accounts.contains(where: { $0.id == accountID }) else { return false }
            try CodexOAuthCredentialStore.save(result.credentials)
            snapshots[accountID] = result.snapshot
            reloadAccounts()
            return true
        } catch {
            if let usageError = error as? CodexUsageError,
               case .unauthorized = usageError {
                do {
                    try CodexOAuthCredentialStore.delete(identityKey: accountID)
                    enabledAccountIDs.remove(accountID)
                    persistEnabledAccounts()
                    snapshots[accountID] = nil
                    reloadAccounts()
                    errorMessage = error.localizedDescription
                } catch {
                    errorMessage = "登录已过期，但删除本机凭据失败：\(error.localizedDescription)"
                }
            }
            accountErrors[accountID] = error.localizedDescription
            return false
        }
    }

    private func reloadAccounts() {
        accounts = CodexOAuthCredentialStore.loadAll().map(CodexAccountInfo.init)
    }
}

private enum CodexTokenIdentity {
    static func userID(from tokens: [String?]) -> String? {
        let decodedClaims = tokens.compactMap { claims(from: $0) }
        let authClaims = decodedClaims.compactMap { $0["https://api.openai.com/auth"] as? [String: Any] }
        return decodedClaims.compactMap { $0["sub"] as? String }.first
            ?? authClaims.compactMap { $0["user_id"] as? String }.first
            ?? authClaims.compactMap { $0["chatgpt_user_id"] as? String }.first
    }

    static func email(from tokens: [String?]) -> String? {
        let decodedClaims = tokens.compactMap { claims(from: $0) }
        let profiles = decodedClaims.compactMap { $0["https://api.openai.com/profile"] as? [String: Any] }
        return profiles.compactMap { $0["email"] as? String }.first
            ?? decodedClaims.compactMap { $0["email"] as? String }.first
    }

    static func name(from tokens: [String?]) -> String? {
        let decodedClaims = tokens.compactMap { claims(from: $0) }
        let profiles = decodedClaims.compactMap { $0["https://api.openai.com/profile"] as? [String: Any] }
        return profiles.compactMap { $0["name"] as? String }.first
            ?? decodedClaims.compactMap { $0["name"] as? String }.first
            ?? decodedClaims.compactMap { $0["preferred_username"] as? String }.first
    }

    static func accountID(from token: String?) -> String? {
        guard let claims = claims(from: token) else { return nil }
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        return (auth?["chatgpt_account_id"] as? String)
            ?? (claims["chatgpt_account_id"] as? String)
    }

    private static func claims(from token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

fileprivate struct CodexOAuthCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let accountID: String
    let expiresAt: Date
    let identityID: String?
    let userID: String?
    let email: String?
    let name: String?

    var resolvedUserID: String? {
        userID ?? CodexTokenIdentity.userID(from: [accessToken])
    }

    var resolvedEmail: String? {
        email ?? CodexTokenIdentity.email(from: [accessToken])
    }

    var resolvedName: String? {
        name ?? CodexTokenIdentity.name(from: [accessToken])
    }

    var identityKey: String {
        if let identityID, !identityID.isEmpty { return identityID }
        if let userID = resolvedUserID, !userID.isEmpty { return "user:\(userID)" }
        if let email = resolvedEmail, !email.isEmpty { return "email:\(email.lowercased())" }
        return "account:\(accountID)"
    }
}

private enum CodexOAuthCredentialStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.ceaser.Quota"
    private static let collectionAccount = "codex.chatgpt.oauth.accounts.v1"
    private static let legacyAccount = "codex.chatgpt.oauth"

    static func loadAll() -> [CodexOAuthCredentials] {
        var credentials = read(account: collectionAccount)
            .flatMap { try? JSONDecoder().decode([CodexOAuthCredentials].self, from: $0) } ?? []

        if let legacyData = read(account: legacyAccount),
           let legacy = try? JSONDecoder().decode(CodexOAuthCredentials.self, from: legacyData) {
            if !credentials.contains(where: { $0.identityKey == legacy.identityKey }) {
                credentials.append(legacy)
            }
            do {
                try persist(credentials)
                try deleteItem(account: legacyAccount)
            } catch {
                // Keep the legacy item so a future launch can retry migration.
            }
        }

        return deduplicated(credentials)
    }

    static func save(_ credential: CodexOAuthCredentials) throws {
        var credentials = loadAll()
        if let index = credentials.firstIndex(where: { $0.identityKey == credential.identityKey }) {
            credentials[index] = credential
        } else {
            credentials.append(credential)
        }
        try persist(credentials)
    }

    static func delete(identityKey: String) throws {
        let credentials = loadAll()
        let remaining = credentials.filter { $0.identityKey != identityKey }
        guard remaining.count != credentials.count else { return }

        try persist(remaining)
        guard !loadAll().contains(where: { $0.identityKey == identityKey }) else {
            throw ProviderCredentialStoreError.verificationFailed
        }
    }

    static func deleteAll() throws {
        try deleteItem(account: collectionAccount)
        try deleteItem(account: legacyAccount)
    }

    private static func deduplicated(_ credentials: [CodexOAuthCredentials]) -> [CodexOAuthCredentials] {
        var result: [CodexOAuthCredentials] = []
        for credential in credentials {
            if let index = result.firstIndex(where: { $0.identityKey == credential.identityKey }) {
                result[index] = credential
            } else {
                result.append(credential)
            }
        }
        return result
    }

    private static func persist(_ credentials: [CodexOAuthCredentials]) throws {
        guard !credentials.isEmpty else {
            try deleteItem(account: collectionAccount)
            return
        }

        let data = try JSONEncoder().encode(deduplicated(credentials))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: collectionAccount
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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

    private static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func deleteItem(account: String) throws {
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

private final class CodexUsageClient {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let issuer = "https://auth.openai.com"
    // Keep this aligned with the Codex SDK version whose wire format was inspected.
    private let codexProtocolVersion = "0.163.0"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestDeviceCode() async throws -> CodexDeviceCode {
        var request = URLRequest(url: URL(string: "\(issuer)/api/accounts/deviceauth/usercode")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientID])

        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else {
            if status == 404 { throw CodexUsageError.deviceCodeUnavailable }
            throw CodexUsageError.httpStatus(status)
        }

        let response: DeviceCodeResponse
        do {
            response = try decoder.decode(DeviceCodeResponse.self, from: data)
        } catch {
            throw CodexUsageError.invalidResponse
        }
        guard let url = URL(string: "\(issuer)/codex/device") else {
            throw CodexUsageError.invalidResponse
        }

        return CodexDeviceCode(
            userCode: response.userCode,
            verificationURL: url,
            deviceAuthID: response.deviceAuthID,
            pollInterval: max(2, min(response.interval?.value ?? 5, 30))
        )
    }

    func completeDeviceCodeLogin(_ flow: CodexDeviceCode) async throws -> CodexOAuthCredentials {
        let deadline = Date().addingTimeInterval(15 * 60)
        var authorization: DeviceCodeAuthorization?

        while true {
            try Task.checkCancellation()
            guard Date() < deadline else { throw CodexUsageError.deviceCodeExpired }

            var request = URLRequest(url: URL(string: "\(issuer)/api/accounts/deviceauth/token")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "device_auth_id": flow.deviceAuthID,
                "user_code": flow.userCode
            ])

            let (data, status) = try await send(request)
            if (200..<300).contains(status) {
                do {
                    authorization = try decoder.decode(DeviceCodeAuthorization.self, from: data)
                    break
                } catch {
                    throw CodexUsageError.invalidResponse
                }
            }
            guard status == 403 || status == 404 else {
                throw CodexUsageError.httpStatus(status)
            }
            try await Task.sleep(nanoseconds: UInt64(flow.pollInterval) * 1_000_000_000)
        }

        try Task.checkCancellation()
        guard let authorization else { throw CodexUsageError.invalidResponse }
        let response = try await exchangeAuthorizationCode(authorization)
        guard response.refreshToken?.isEmpty == false else {
            throw CodexUsageError.invalidResponse
        }
        guard let accountID = response.resolvedAccountID
                ?? accountID(from: response.accessToken)
                ?? accountID(from: response.idToken) else {
            throw CodexUsageError.missingAccountID
        }
        return makeCredentials(response, accountID: accountID, previousCredentials: nil)
    }

    func fetchUsage(
        using initialCredentials: CodexOAuthCredentials
    ) async throws -> (snapshot: CodexUsageSnapshot, credentials: CodexOAuthCredentials) {
        var credentials = initialCredentials
        if credentials.expiresAt.timeIntervalSinceNow < 300 {
            credentials = try await refresh(credentials)
        }

        do {
            return (try await requestUsage(credentials), credentials)
        } catch CodexUsageError.unauthorized {
            credentials = try await refresh(credentials)
            return (try await requestUsage(credentials), credentials)
        }
    }

    private func requestUsage(_ credentials: CodexOAuthCredentials) async throws -> CodexUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")

        let (data, status) = try await send(request)
        if status == 401 { throw CodexUsageError.unauthorized }
        guard (200..<300).contains(status) else {
            throw CodexUsageError.httpStatus(status)
        }

        let response: CodexUsageResponse
        do {
            response = try decoder.decode(CodexUsageResponse.self, from: data)
        } catch {
            throw CodexUsageError.invalidResponse
        }

        var windows: [CodexUsageWindow] = []
        if let primary = response.rateLimit.primaryWindow {
            windows.append(makeWindow(primary, id: "primary"))
        }
        if let secondary = response.rateLimit.secondaryWindow {
            windows.append(makeWindow(secondary, id: "secondary"))
        }
        guard !windows.isEmpty else { throw CodexUsageError.noUsageWindows }

        return CodexUsageSnapshot(
            planType: response.planTypeSnake ?? response.planTypeCamel,
            windows: windows,
            resetCreditsAvailable: response.resetCredits?.availableCount?.value,
            updatedAt: Date()
        )
    }

    private func refresh(_ credentials: CodexOAuthCredentials) async throws -> CodexOAuthCredentials {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": clientID
        ])

        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else {
            if status == 400 || status == 401 { throw CodexUsageError.unauthorized }
            throw CodexUsageError.httpStatus(status)
        }

        let response: OAuthTokenResponse
        do {
            response = try decoder.decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw CodexUsageError.invalidResponse
        }
        let accountID = response.resolvedAccountID
            ?? accountID(from: response.accessToken)
            ?? credentials.accountID
        return makeCredentials(response, accountID: accountID, previousCredentials: credentials)
    }

    private func exchangeAuthorizationCode(
        _ authorization: DeviceCodeAuthorization
    ) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "code": authorization.authorizationCode,
            "redirect_uri": "\(issuer)/deviceauth/callback",
            "client_id": clientID,
            "code_verifier": authorization.codeVerifier
        ])

        let (data, status) = try await send(request)
        guard (200..<300).contains(status) else {
            throw CodexUsageError.httpStatus(status)
        }
        do {
            return try decoder.decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw CodexUsageError.invalidResponse
        }
    }

    private func makeCredentials(
        _ response: OAuthTokenResponse,
        accountID: String,
        previousCredentials: CodexOAuthCredentials?
    ) -> CodexOAuthCredentials {
        let tokens = [response.idToken, response.accessToken]
        let userID = CodexTokenIdentity.userID(from: tokens) ?? previousCredentials?.resolvedUserID
        let email = CodexTokenIdentity.email(from: tokens) ?? previousCredentials?.resolvedEmail
        let name = CodexTokenIdentity.name(from: tokens) ?? previousCredentials?.resolvedName
        let identityID = previousCredentials?.identityKey
            ?? userID.map { "user:\($0)" }
            ?? email.map { "email:\($0.lowercased())" }
            ?? "account:\(accountID)"

        return CodexOAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? previousCredentials?.refreshToken ?? "",
            accountID: accountID,
            expiresAt: Date().addingTimeInterval(response.expiresIn?.value ?? 3600),
            identityID: identityID,
            userID: userID,
            email: email,
            name: name
        )
    }

    private func makeWindow(_ wire: UsageWindowResponse, id: String) -> CodexUsageWindow {
        let seconds = wire.windowSeconds?.value
        let title: String
        if let seconds {
            if (10_800...21_600).contains(seconds) {
                title = "5-hour limit"
            } else if (500_000...700_000).contains(seconds) {
                title = "Weekly limit"
            } else if (2_000_000...3_000_000).contains(seconds) {
                title = "Monthly limit"
            } else if seconds >= 86_400 {
                title = "\(Int((seconds / 86_400).rounded()))-day limit"
            } else {
                title = id == "primary" ? "Primary limit" : "Secondary limit"
            }
        } else {
            title = id == "primary" ? "Primary limit" : "Secondary limit"
        }
        let resetAt: Date?
        if let timestamp = wire.resetAt?.value {
            resetAt = Date(timeIntervalSince1970: timestamp)
        } else if let seconds = wire.resetAfterSeconds?.value {
            resetAt = Date().addingTimeInterval(seconds)
        } else {
            resetAt = nil
        }
        return CodexUsageWindow(
            id: id,
            title: title,
            usedPercent: wire.usedPercent?.value,
            resetAt: resetAt
        )
    }

    private var appUserAgent: String {
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)"
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return "codex_cli_rs/\(codexProtocolVersion) (iOS \(osVersion); \(architecture))"
    }

    private func formBody(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func accountID(from token: String?) -> String? {
        CodexTokenIdentity.accountID(from: token)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageError.invalidResponse
        }
        return (data, httpResponse.statusCode)
    }
}

private struct DeviceCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: CodexFlexibleInt?

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case alternateUserCode = "usercode"
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        userCode = try container.decodeIfPresent(String.self, forKey: .userCode)
            ?? container.decode(String.self, forKey: .alternateUserCode)
        interval = try container.decodeIfPresent(CodexFlexibleInt.self, forKey: .interval)
    }
}

private struct DeviceCodeAuthorization: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: FlexibleDouble?
    let accountID: String?
    let alternateAccountID: String?

    var resolvedAccountID: String? {
        accountID ?? alternateAccountID
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case accountID = "chatgpt_account_id"
        case alternateAccountID = "account_id"
    }
}

private struct CodexUsageResponse: Decodable {
    let planTypeSnake: String?
    let planTypeCamel: String?
    let rateLimit: RateLimitResponse
    let resetCredits: ResetCreditsResponse?

    enum CodingKeys: String, CodingKey {
        case planTypeSnake = "plan_type"
        case planTypeCamel = "planType"
        case rateLimit = "rate_limit"
        case resetCredits = "rate_limit_reset_credits"
    }
}

private struct RateLimitResponse: Decodable {
    let primaryWindow: UsageWindowResponse?
    let secondaryWindow: UsageWindowResponse?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct UsageWindowResponse: Decodable {
    let usedPercent: FlexibleDouble?
    let windowSeconds: FlexibleDouble?
    let resetAt: FlexibleDouble?
    let resetAfterSeconds: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
        case resetAfterSeconds = "reset_after_seconds"
    }
}

private struct ResetCreditsResponse: Decodable {
    let availableCount: CodexFlexibleInt?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}

private struct CodexFlexibleInt: Decodable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(String.self), let integer = Int(value) {
            self.value = integer
        } else if let value = try? container.decode(Double.self) {
            self.value = Int(value)
        } else {
            throw DecodingError.typeMismatch(
                Int.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected an integer")
            )
        }
    }
}
