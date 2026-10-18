import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ProviderStore

    private var balanceProviders: [ProviderID] {
        ProviderID.allCases.filter { $0.kind == .balance }
    }

    private var costProviders: [ProviderID] {
        ProviderID.allCases.filter { $0.kind == .cost }
    }

    private var manualProviders: [ProviderID] {
        ProviderID.allCases.filter { $0.kind == .manual }
    }

    var body: some View {
        ZStack {
            QuotaColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providerGroup(title: "balance providers", providers: balanceProviders)
                    providerGroup(title: "usage providers", providers: costProviders)
                    providerGroup(title: "manual", providers: manualProviders)

                    Text(appVersion)
                        .font(.caption)
                        .foregroundColor(QuotaColors.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private func providerGroup(title: String, providers: [ProviderID]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundColor(QuotaColors.secondaryText)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(providers.indices, id: \.self) { index in
                    let provider = providers[index]

                    ProviderSettingsRow(provider: provider)

                    if index < providers.count - 1 {
                        Divider()
                            .overlay(QuotaColors.separator)
                            .padding(.leading, 58)
                    }
                }
            }
            .background(QuotaColors.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(cardBorder())
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?):
            return "Quota \(version) (\(build))"
        case let (version?, nil):
            return "Quota \(version)"
        default:
            return "Quota 1.0"
        }
    }
}

private struct ProviderSettingsRow: View {
    @EnvironmentObject private var store: ProviderStore

    let provider: ProviderID

    private var statusText: String {
        if store.isEnabled(provider) {
            return "enabled"
        }
        if store.isConfigured(provider) {
            return "ready"
        }
        return provider.kind == .manual ? "console" : "setup"
    }

    var body: some View {
        NavigationLink {
            ProviderConfigurationView(provider: provider)
        } label: {
            HStack(spacing: 12) {
                ProviderLogoView(provider: provider, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundColor(QuotaColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(provider.subtitle)
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(store.isEnabled(provider) ? provider.tint : QuotaColors.tertiaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(QuotaColors.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderConfigurationView: View {
    @EnvironmentObject private var store: ProviderStore

    let provider: ProviderID

    @State private var draftValues: [ProviderFieldKey: String] = [:]
    @State private var revealedFields: Set<ProviderFieldKey> = []
    @State private var localError: String?
    @State private var savedMessage: String?
    @State private var showsRemoveConfirmation = false

    var body: some View {
        ZStack {
            QuotaColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if provider.kind == .manual {
                        manualProviderCard
                    } else {
                        configurationCard

                        if store.isConfigured(provider) {
                            Button {
                                showsRemoveConfirmation = true
                            } label: {
                                Label("移除配置", systemImage: "trash")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(QuotaColors.danger)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .background(QuotaColors.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if provider.kind != .manual {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.isEnabled(provider) },
                            set: { setEnabledState($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(ProviderEnableToggleStyle())
                    .disabled(!canToggleEnabled)
                    .opacity(canToggleEnabled ? 1 : 0.42)
                    .accessibilityLabel(store.isEnabled(provider) ? "禁用厂商" : "启用厂商")
                }
            }
        }
        .onAppear(perform: loadDraftValues)
        .confirmationDialog(
            "移除 \(provider.displayName) 配置？",
            isPresented: $showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) {
                store.removeConfiguration(for: provider)
                draftValues = [:]
                savedMessage = nil
                localError = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移除后该厂商会立即从 Usage 页面隐藏。")
        }
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.headline)
                        .foregroundColor(QuotaColors.primaryText)

                    Text(store.isConfigured(provider) ? "已保存到本机钥匙串" : "尚未完成配置")
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                }

                Spacer()

            }

            Text(provider.configurationHint)
                .font(.caption)
                .foregroundColor(QuotaColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(provider.fields) { field in
                configurationField(field)
            }

            if let localError {
                Text(localError)
                    .font(.footnote)
                    .foregroundColor(QuotaColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let savedMessage {
                Text(savedMessage)
                    .font(.footnote)
                    .foregroundColor(QuotaColors.secondaryText)
            } else if let error = store.error(for: provider) {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(QuotaColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                saveConfiguration(enable: store.isEnabled(provider))
            } label: {
                Text("保存配置")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)

            if let updatedAt = store.lastUpdated(for: provider) {
                Text("最近更新：\(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(QuotaColors.tertiaryText)
            }
        }
        .padding(18)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder())
    }

    private var manualProviderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ProviderLogoView(provider: provider, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(.headline)
                        .foregroundColor(QuotaColors.primaryText)

                    Text("No public balance API")
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                }

                Spacer()
            }

            Text(provider.configurationHint)
                .font(.subheadline)
                .foregroundColor(QuotaColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let consoleURL = provider.consoleURL {
                Link(destination: consoleURL) {
                    Label("打开官方控制台", systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder())
    }

    private var canSave: Bool {
        provider.fields.allSatisfy { field in
            let draft = draftValues[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !draft.isEmpty || store.storedValue(provider, field: field.key) != nil
        }
    }

    private var canToggleEnabled: Bool {
        store.isEnabled(provider) || store.isConfigured(provider) || canSave
    }

    private func configurationField(_ field: ProviderFieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(QuotaColors.primaryText)

            HStack(spacing: 8) {
                Group {
                    if field.isSecret, !revealedFields.contains(field.key) {
                        SecureField(field.placeholder, text: binding(for: field.key))
                    } else {
                        TextField(field.placeholder, text: binding(for: field.key))
                    }
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(field.keyboard == .url ? .URL : .asciiCapable)
                .font(.system(.subheadline, design: .monospaced))

                if field.isSecret {
                    Button {
                        if revealedFields.contains(field.key) {
                            revealedFields.remove(field.key)
                        } else {
                            revealedFields.insert(field.key)
                        }
                    } label: {
                        Image(
                            systemName: revealedFields.contains(field.key)
                                ? "eye.slash"
                                : "eye"
                        )
                        .foregroundColor(QuotaColors.secondaryText)
                        .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel(
                        revealedFields.contains(field.key) ? "隐藏内容" : "显示内容"
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(QuotaColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(QuotaColors.separator, lineWidth: 1)
            )

            if let existing = store.storedValue(provider, field: field.key) {
                Text(
                    field.isSecret
                        ? "已保存：\(ProviderCredentialStore.mask(existing))"
                        : "当前值：\(existing)"
                )
                .font(.caption2)
                .foregroundColor(QuotaColors.tertiaryText)
                .lineLimit(1)
            }
        }
    }

    private func binding(for field: ProviderFieldKey) -> Binding<String> {
        Binding(
            get: { draftValues[field] ?? "" },
            set: { draftValues[field] = $0 }
        )
    }

    private func loadDraftValues() {
        for field in provider.fields where !field.isSecret {
            draftValues[field.key] = store.storedValue(provider, field: field.key) ?? ""
        }
    }

    private func setEnabledState(_ enabled: Bool) {
        guard enabled else {
            store.setEnabled(false, for: provider)
            return
        }

        if store.isConfigured(provider), !hasPendingSecretInput {
            store.setEnabled(true, for: provider)
        } else {
            saveConfiguration(enable: true)
        }
    }

    private var hasPendingSecretInput: Bool {
        provider.fields.contains { field in
            guard field.isSecret else {
                return false
            }
            let value = draftValues[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !value.isEmpty
        }
    }

    private func saveConfiguration(enable: Bool) {
        do {
            try store.saveConfiguration(
                provider: provider,
                values: draftValues,
                enable: enable
            )

            for field in provider.fields where field.isSecret {
                draftValues[field.key] = ""
                revealedFields.remove(field.key)
            }

            localError = nil
            savedMessage = enable ? "配置已保存，已启用并开始刷新。" : "配置已保存。"
        } catch {
            savedMessage = nil
            localError = error.localizedDescription
        }
    }
}

private struct ProviderEnableToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        configuration.isOn
                            ? Color(red: 0.18, green: 0.68, blue: 0.36)
                            : Color(red: 0.94, green: 0.52, blue: 0.16)
                    )
                    .frame(width: 51, height: 31)

                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .padding(2)
                    .shadow(color: Color.black.opacity(0.16), radius: 1.5, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
