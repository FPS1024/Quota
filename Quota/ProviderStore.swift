import Foundation

@MainActor
final class ProviderStore: ObservableObject {
    @Published private(set) var enabledProviderIDs: Set<ProviderID> = []
    @Published private(set) var snapshots: [ProviderUsageSnapshot] = []
    @Published private(set) var errors: [ProviderID: String] = [:]
    @Published private(set) var loadingProviders: Set<ProviderID> = []
    @Published private(set) var lastUpdated: [ProviderID: Date] = [:]

    private let client: ProviderAPIClient
    private let defaults = UserDefaults.standard

    private static let enabledProvidersKey = "enabledProviderIDs.v1"
    private static let migrationKey = "providerMigration.v1"

    init(client: ProviderAPIClient = ProviderAPIClient()) {
        self.client = client
        restoreEnabledProviders()
    }

    var enabledProviders: [ProviderID] {
        ProviderID.allCases.filter { enabledProviderIDs.contains($0) }
    }

    func isEnabled(_ provider: ProviderID) -> Bool {
        enabledProviderIDs.contains(provider)
    }

    func isLoading(_ provider: ProviderID) -> Bool {
        loadingProviders.contains(provider)
    }

    func isConfigured(_ provider: ProviderID) -> Bool {
        guard provider.kind != .manual else {
            return false
        }

        return provider.fields.allSatisfy { field in
            ProviderCredentialStore.read(provider: provider, field: field.key)?.isEmpty == false
        }
    }

    func storedValue(_ provider: ProviderID, field: ProviderFieldKey) -> String? {
        ProviderCredentialStore.read(provider: provider, field: field)
    }

    func maskedStoredValue(_ provider: ProviderID, field: ProviderFieldKey) -> String? {
        guard let value = storedValue(provider, field: field) else {
            return nil
        }
        return ProviderCredentialStore.mask(value)
    }

    func snapshots(for provider: ProviderID) -> [ProviderUsageSnapshot] {
        snapshots.filter { $0.provider == provider }
    }

    func error(for provider: ProviderID) -> String? {
        errors[provider]
    }

    func lastUpdated(for provider: ProviderID) -> Date? {
        lastUpdated[provider]
    }

    func setEnabled(_ enabled: Bool, for provider: ProviderID) {
        guard provider.kind != .manual else {
            return
        }

        if enabled {
            guard isConfigured(provider) else {
                return
            }
            enabledProviderIDs.insert(provider)
        } else {
            enabledProviderIDs.remove(provider)
            snapshots.removeAll { $0.provider == provider }
            errors.removeValue(forKey: provider)
            lastUpdated.removeValue(forKey: provider)
        }

        persistEnabledProviders()

        if enabled {
            Task {
                await refreshProvider(provider)
            }
        }
    }

    func saveConfiguration(
        provider: ProviderID,
        values: [ProviderFieldKey: String],
        enable: Bool
    ) throws {
        guard provider.kind != .manual else {
            throw ProviderStoreError.providerNotConfigurable
        }

        for field in provider.fields {
            let draft = values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let existing = storedValue(provider, field: field.key) ?? ""
            let value = draft.isEmpty ? existing : draft

            if !value.isEmpty {
                try ProviderCredentialStore.save(value, provider: provider, field: field.key)
            }
        }

        guard isConfigured(provider) else {
            throw ProviderStoreError.missingConfiguration
        }

        if enable {
            enabledProviderIDs.insert(provider)
        } else {
            enabledProviderIDs.remove(provider)
            snapshots.removeAll { $0.provider == provider }
            errors.removeValue(forKey: provider)
            lastUpdated.removeValue(forKey: provider)
        }
        persistEnabledProviders()

        if enable {
            Task {
                await refreshProvider(provider)
            }
        }
    }

    func removeConfiguration(for provider: ProviderID) {
        ProviderCredentialStore.deleteAll(provider: provider)
        enabledProviderIDs.remove(provider)
        snapshots.removeAll { $0.provider == provider }
        errors.removeValue(forKey: provider)
        lastUpdated.removeValue(forKey: provider)
        persistEnabledProviders()
    }

    func refreshProvider(_ provider: ProviderID) async {
        guard isEnabled(provider), isConfigured(provider) else {
            return
        }

        loadingProviders.insert(provider)
        errors.removeValue(forKey: provider)
        defer { loadingProviders.remove(provider) }

        do {
            let snapshots = try await client.fetchUsage(
                provider: provider,
                credentials: configuration(for: provider)
            )
            guard isEnabled(provider) else {
                return
            }
            apply(snapshots: snapshots, for: provider)
            lastUpdated[provider] = Date()
        } catch is CancellationError {
            return
        } catch {
            errors[provider] = error.localizedDescription
        }
    }

    func refreshEnabledProviders() async -> ProviderRefreshResult {
        let providers = enabledProviders.filter { isEnabled($0) && isConfigured($0) }

        guard !providers.isEmpty else {
            return ProviderRefreshResult(
                successfulProviders: 0,
                failedProviders: [],
                cancelledProviders: []
            )
        }

        for provider in providers {
            loadingProviders.insert(provider)
            errors.removeValue(forKey: provider)
        }

        let tasks = providers.map { provider -> Task<(ProviderID, Result<[ProviderUsageSnapshot], Error>), Never> in
            let credentials = configuration(for: provider)
            let client = self.client

            return Task {
                do {
                    let snapshots = try await client.fetchUsage(
                        provider: provider,
                        credentials: credentials
                    )
                    return (provider, .success(snapshots))
                } catch {
                    return (provider, .failure(error))
                }
            }
        }

        var successful = 0
        var failed: [ProviderID] = []
        var cancelled: [ProviderID] = []

        for task in tasks {
            let (provider, result) = await task.value
            loadingProviders.remove(provider)

            guard isEnabled(provider) else {
                continue
            }

            switch result {
            case .success(let snapshots):
                apply(snapshots: snapshots, for: provider)
                lastUpdated[provider] = Date()
                successful += 1
            case .failure(let error):
                if error is CancellationError {
                    cancelled.append(provider)
                } else {
                    errors[provider] = error.localizedDescription
                    failed.append(provider)
                }
            }
        }

        return ProviderRefreshResult(
            successfulProviders: successful,
            failedProviders: failed,
            cancelledProviders: cancelled
        )
    }

    private func configuration(for provider: ProviderID) -> [ProviderFieldKey: String] {
        var values: [ProviderFieldKey: String] = [:]

        for field in provider.fields {
            if let value = storedValue(provider, field: field.key) {
                values[field.key] = value
            }
        }

        return values
    }

    private func apply(snapshots newSnapshots: [ProviderUsageSnapshot], for provider: ProviderID) {
        snapshots.removeAll { $0.provider == provider }
        snapshots.append(contentsOf: newSnapshots)
        snapshots.sort { left, right in
            let leftIndex = ProviderID.allCases.firstIndex(of: left.provider) ?? 0
            let rightIndex = ProviderID.allCases.firstIndex(of: right.provider) ?? 0

            if leftIndex == rightIndex {
                return left.id < right.id
            }
            return leftIndex < rightIndex
        }
        errors.removeValue(forKey: provider)
    }

    private func restoreEnabledProviders() {
        let storedIDs = defaults.stringArray(forKey: Self.enabledProvidersKey) ?? []
        enabledProviderIDs = Set(storedIDs.compactMap(ProviderID.init(rawValue:)))

        if !defaults.bool(forKey: Self.migrationKey) {
            if ProviderCredentialStore.migrateLegacyDeepSeekKeyIfNeeded() {
                enabledProviderIDs.insert(.deepseek)
            }
            defaults.set(true, forKey: Self.migrationKey)
        }

        enabledProviderIDs = enabledProviderIDs.filter { isConfigured($0) }
        persistEnabledProviders()
    }

    private func persistEnabledProviders() {
        let values = enabledProviderIDs
            .map(\.rawValue)
            .sorted()
        defaults.set(values, forKey: Self.enabledProvidersKey)
    }
}
