import SwiftUI
import UIKit

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
    @EnvironmentObject private var codexUsageStore: CodexUsageStore

    let provider: ProviderID

    private var statusText: String {
        if provider == .openai, codexUsageStore.isEnabled {
            return "enabled"
        }
        if store.isEnabled(provider) {
            return "enabled"
        }
        if provider == .openai, codexUsageStore.isAuthenticated {
            return "ready"
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

                    Text(provider == .openai ? "API costs · Codex plan usage" : provider.subtitle)
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(
                        store.isEnabled(provider) || (provider == .openai && codexUsageStore.isEnabled)
                            ? provider.tint
                            : QuotaColors.tertiaryText
                    )
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

                        if provider == .openai {
                            CodexUsageSettingsCard()
                        }

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

private struct CodexUsageSettingsCard: View {
    @EnvironmentObject private var store: CodexUsageStore
    @State private var accountToRemove: CodexAccountInfo?
    @State private var copiedDeviceCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 11) {
                ProviderLogoView(provider: .openai, size: 40, assetName: "ProviderCodex")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex")
                        .font(.headline)
                        .foregroundColor(QuotaColors.primaryText)

                    Text(store.isAuthenticated
                        ? "\(store.accounts.count) 个账号 · \(store.enabledAccounts.count) 个显示用量"
                        : "ChatGPT 计划额度")
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                }

                Spacer()

            }

            if !store.accounts.isEmpty {
                VStack(spacing: 10) {
                    ForEach(store.accounts) { account in
                        accountRow(account)
                    }
                }
            }

            if let deviceCode = store.deviceCode {
                VStack(alignment: .leading, spacing: 10) {
                    Text("在浏览器中打开验证页面，然后输入这组一次性配对码。")
                        .font(.subheadline)
                        .foregroundColor(QuotaColors.secondaryText)

                    Button {
                        UIPasteboard.general.string = deviceCode.userCode
                        copiedDeviceCode = true
                    } label: {
                        HStack(spacing: 12) {
                            Text(deviceCode.userCode)
                                .font(.system(.title2, design: .monospaced).weight(.bold))
                                .foregroundColor(QuotaColors.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Spacer(minLength: 4)

                            Label(
                                copiedDeviceCode ? "已复制" : "复制",
                                systemImage: copiedDeviceCode ? "checkmark" : "doc.on.doc"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundColor(ProviderID.openai.tint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(ProviderID.openai.tint.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copiedDeviceCode ? "配对码已复制" : "复制 Codex 配对码")

                    Link(destination: deviceCode.verificationURL) {
                        Label("打开 Codex 验证页面", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    HStack(spacing: 8) {
                        ProgressView()
                        Text("等待浏览器确认登录…")
                            .font(.caption)
                            .foregroundColor(QuotaColors.secondaryText)
                        Spacer()
                        Button("取消") { store.cancelLogin() }
                            .font(.caption.weight(.medium))
                    }
                }
            } else if store.isLoggingIn {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在准备设备验证码…")
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                    Spacer()
                    Button("取消") { store.cancelLogin() }
                        .font(.caption.weight(.medium))
                }
            }

            if store.accounts.isEmpty {
                Text("使用 ChatGPT device code 登录。额度凭据仅保存在本机钥匙串。")
                    .font(.caption)
                    .foregroundColor(QuotaColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("每个账号单独设置是否显示用量，额度和登录状态也分开保存。")
                    .font(.caption)
                    .foregroundColor(QuotaColors.secondaryText)
            }

            if !store.isLoggingIn {
                Button {
                    store.beginLogin()
                } label: {
                    Label(
                        store.isAuthenticated ? "添加另一个 Codex 账号" : "使用 ChatGPT 登录 Codex",
                        systemImage: store.isAuthenticated ? "person.badge.plus" : "arrow.right.circle"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(QuotaColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("额度读取使用 Codex 内部接口，官方调整接口时可能需要更新。")
                .font(.caption2)
                .foregroundColor(QuotaColors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder())
        .confirmationDialog(
            "退出此 Codex 账号？",
            isPresented: Binding(
                get: { accountToRemove != nil },
                set: { if !$0 { accountToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let selectedAccount = accountToRemove {
                Button("退出登录", role: .destructive) {
                    store.signOut(accountID: selectedAccount.id)
                    accountToRemove = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从本机删除此账号的登录凭据和额度数据。")
        }
        .onChange(of: store.deviceCode?.userCode) { _ in
            copiedDeviceCode = false
        }
    }

    private func accountRow(_ account: CodexAccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 3) {
                    if account.displayName.caseInsensitiveCompare(account.email ?? "") != .orderedSame {
                        Text(account.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(QuotaColors.primaryText)
                            .lineLimit(1)
                    }
                    Text(account.email ?? account.detail)
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                if store.loadingAccountIDs.contains(account.id) {
                    ProgressView()
                } else if store.snapshots[account.id] != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.green)
                        .accessibilityLabel("额度已同步")
                }

                Toggle("", isOn: Binding(
                    get: { store.isEnabled(accountID: account.id) },
                    set: { store.setEnabled($0, for: account.id) }
                ))
                .labelsHidden()
                .toggleStyle(ProviderEnableToggleStyle())
                .accessibilityLabel(store.isEnabled(accountID: account.id)
                    ? "关闭此账号的 Codex 用量显示"
                    : "显示此账号的 Codex 用量")
            }

            if let snapshot = store.snapshots[account.id] {
                Text(snapshot.windows.map { window in
                    guard let remaining = window.remainingPercent else {
                        return "\(window.title)：—"
                    }
                    return "\(window.title)：剩余 \(Int(remaining.rounded()))%"
                }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(QuotaColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = store.accountErrors[account.id] {
                Text(error)
                    .font(.caption)
                    .foregroundColor(QuotaColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                accountToRemove = account
            } label: {
                Label("退出此账号", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(QuotaColors.danger)
                    .background(QuotaColors.danger.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(QuotaColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                            : Color(uiColor: .systemGray3)
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
