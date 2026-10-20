import SwiftUI

enum QuotaColors {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let raisedSurface = Color(uiColor: .systemBackground)
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let tertiaryText = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator)
    static let accent = Color(uiColor: .label)
    static let danger = Color(uiColor: .systemRed)
    static let usageBadgeTint = Color(red: 0.22, green: 0.43, blue: 0.62)
}

extension ProviderID {
    var tint: Color {
        switch self {
        case .deepseek:
            return Color(red: 0.22, green: 0.43, blue: 0.62)
        case .moonshot:
            return Color(red: 0.34, green: 0.39, blue: 0.60)
        case .openrouter:
            return Color(red: 0.25, green: 0.48, blue: 0.44)
        case .xai:
            return Color(red: 0.36, green: 0.36, blue: 0.38)
        case .openai:
            return Color(red: 0.12, green: 0.47, blue: 0.45)
        case .anthropic:
            return Color(red: 0.60, green: 0.38, blue: 0.28)
        case .gemini:
            return Color(red: 0.24, green: 0.46, blue: 0.75)
        case .qwen:
            return Color(red: 0.58, green: 0.43, blue: 0.21)
        }
    }
}

struct ProviderLogoView: View {
    let provider: ProviderID
    var size: CGFloat = 38
    var assetName: String? = nil

    private var logoScale: CGFloat {
        provider == .gemini ? 0.75 : 1
    }

    var body: some View {
        Image(assetName ?? provider.logoAssetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size * logoScale, height: size * logoScale)
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

struct BalanceView: View {
    @EnvironmentObject private var store: ProviderStore
    @EnvironmentObject private var codexUsageStore: CodexUsageStore

    let openSettings: () -> Void

    @State private var refreshFeedback: RefreshFeedback?
    @State private var feedbackGeneration = UUID()

    var body: some View {
        ZStack {
            QuotaColors.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let refreshFeedback {
                        RefreshFeedbackBanner(feedback: refreshFeedback)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if !codexUsageStore.enabledAccounts.isEmpty {
                        CodexUsageSection()
                    }

                    if store.enabledProviders.isEmpty
                        && codexUsageStore.enabledAccounts.isEmpty {
                        EmptyProvidersCard(openSettings: openSettings)
                    } else {
                        ForEach(store.enabledProviders) { provider in
                            ProviderUsageSection(provider: provider)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.2), value: refreshFeedback?.id)
            }
            .refreshable {
                await refreshAll()
            }
        }
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if !store.enabledProviders.isEmpty, store.snapshots.isEmpty {
                _ = await store.refreshEnabledProviders()
            }
            if codexUsageStore.isEnabled, codexUsageStore.snapshots.isEmpty {
                _ = await codexUsageStore.refreshAll()
            }
        }
    }

    @MainActor
    private func refreshAll() async {
        let refreshTask = Task { @MainActor in
            await performRefresh()
        }

        await refreshTask.value
    }

    @MainActor
    private func performRefresh() async {
        guard !store.enabledProviders.isEmpty || codexUsageStore.isEnabled else {
            showTemporarily(
                RefreshFeedback(kind: .neutral, message: "没有已启用的厂商")
            )
            return
        }

        let codexSucceeded = codexUsageStore.isEnabled
            ? await codexUsageStore.refreshAll()
            : true
        let result = await store.refreshEnabledProviders()

        if !result.failedProviders.isEmpty || !codexSucceeded {
            showTemporarily(
                RefreshFeedback(kind: .failure, message: "刷新失败")
            )
        } else if !result.cancelledProviders.isEmpty {
            showTemporarily(
                RefreshFeedback(kind: .neutral, message: "刷新未完成")
            )
        } else if result.successfulProviders > 0 || codexUsageStore.isEnabled {
            showTemporarily(
                RefreshFeedback(kind: .success, message: "刷新成功")
            )
        } else {
            showTemporarily(
                RefreshFeedback(kind: .neutral, message: "没有可刷新的配置")
            )
        }
    }

    @MainActor
    private func showTemporarily(_ feedback: RefreshFeedback) {
        let generation = UUID()
        feedbackGeneration = generation

        withAnimation(.easeInOut(duration: 0.2)) {
            refreshFeedback = feedback
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard feedbackGeneration == generation else {
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                refreshFeedback = nil
            }
        }
    }
}

private struct CodexUsageSection: View {
    @EnvironmentObject private var store: CodexUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(store.enabledAccounts) { account in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        ProviderLogoView(provider: .openai, size: 24, assetName: "ProviderCodex")

                        Text(account.email ?? account.detail)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(QuotaColors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 2)

                    CodexAccountUsageCard(account: account)
                }
            }
        }
    }
}

private struct CodexAccountUsageCard: View {
    @EnvironmentObject private var store: CodexUsageStore

    let account: CodexAccountInfo

    private var snapshot: CodexUsageSnapshot? {
        store.snapshots[account.id]
    }

    private var planLabel: String {
        guard let rawPlan = snapshot?.planType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlan.isEmpty else {
            return "ChatGPT"
        }

        var key = rawPlan.lowercased().replacingOccurrences(of: "-", with: "_")
        if key.hasPrefix("chatgpt_") {
            key.removeFirst("chatgpt_".count)
        }
        if key.hasSuffix("_plan") {
            key.removeLast("_plan".count)
        }

        let knownPlans: [String: String] = [
            "free": "Free",
            "free_workspace": "Free Workspace",
            "go": "Go",
            "plus": "Plus",
            "pro": "Pro",
            "prolite": "Pro",
            "promax": "Pro Max",
            "team": "Team",
            "business": "Business",
            "self_serve_business_prolite": "Business Pro",
            "self_serve_business_usage_based": "Business",
            "enterprise": "Enterprise",
            "ent26": "Enterprise",
            "enterprise_cbp_automation": "Enterprise",
            "enterprise_cbp_usage_based": "Enterprise",
            "education": "Education",
            "edu": "Education",
            "edu_plus": "Edu Plus",
            "edu_pro": "Edu Pro",
            "sci": "Academic Researchers",
            "sci_plus": "Academic Researchers Plus",
            "hc": "Enterprise",
            "quorum": "Quorum",
            "k12": "K-12"
        ]
        let title = knownPlans[key] ?? key
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
        return "ChatGPT · \(title)"
    }

    private func updatedTimestamp(_ date: Date) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(Locale(identifier: "en_US"))
        return "Updated \(date.formatted(style))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(planLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(QuotaColors.usageBadgeTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(QuotaColors.usageBadgeTint.opacity(0.10))
                    .clipShape(Capsule())

                Spacer(minLength: 0)
            }

            if let snapshot {
                ForEach(snapshot.windows) { window in
                    CodexUsageWindowRow(window: window)
                }

                Text(updatedTimestamp(snapshot.updatedAt))
                    .font(.caption2)
                    .foregroundColor(QuotaColors.tertiaryText)
            } else if store.loadingAccountIDs.contains(account.id) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Fetching Codex usage…")
                        .font(.caption)
                        .foregroundColor(QuotaColors.secondaryText)
                }
            } else {
                Text(store.accountErrors[account.id] ?? "No usage data returned by Codex yet.")
                    .font(.caption)
                    .foregroundColor(store.accountErrors[account.id] == nil
                        ? QuotaColors.secondaryText
                        : QuotaColors.danger)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await store.refresh(accountID: account.id) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .font(.caption.weight(.medium))
            }

            if let errorMessage = store.accountErrors[account.id], snapshot != nil {
                ProviderInlineError(message: errorMessage)
            }
        }
        .padding(16)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder())
    }
}

private struct CodexUsageWindowRow: View {
    let window: CodexUsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(QuotaColors.primaryText)

                Spacer()

                if let remaining = window.remainingPercent {
                    Text("\(Int(remaining.rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(QuotaColors.primaryText)
                } else {
                    Text("—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(QuotaColors.tertiaryText)
                }
            }

            if let remaining = window.remainingPercent {
                ProgressView(value: remaining, total: 100)
                    .tint(Color(red: 0.18, green: 0.68, blue: 0.36))
            }

            if let resetAt = window.resetAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(resetCountdown(until: resetAt, now: context.date))
                        .font(.caption2)
                        .foregroundColor(QuotaColors.tertiaryText)
                }
            }
        }
    }

    private func resetCountdown(until resetAt: Date, now: Date) -> String {
        let secondsRemaining = max(0, Int(ceil(resetAt.timeIntervalSince(now))))
        guard secondsRemaining > 0 else { return "Resetting" }

        let days = secondsRemaining / 86_400
        let hours = (secondsRemaining % 86_400) / 3_600
        let minutes = (secondsRemaining % 3_600) / 60
        let seconds = secondsRemaining % 60

        if days > 0 {
            return hours > 0 ? "Resets in \(days)d \(hours)h" : "Resets in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        }
        if minutes > 0 { return "Resets in \(minutes)m" }
        return "Resets in \(seconds)s"
    }
}

private struct ProviderUsageSection: View {
    @EnvironmentObject private var store: ProviderStore

    let provider: ProviderID

    private var providerSnapshots: [ProviderUsageSnapshot] {
        store.snapshots(for: provider)
    }

    private var errorMessage: String? {
        store.error(for: provider)
    }

    private var isLoading: Bool {
        store.isLoading(provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                ProviderLogoView(provider: provider, size: 24)

                Text(provider.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(QuotaColors.primaryText)

                Spacer()
            }
            .padding(.horizontal, 2)

            if isLoading, providerSnapshots.isEmpty {
                ProviderLoadingCard(provider: provider)
            } else if providerSnapshots.isEmpty, let errorMessage {
                ProviderErrorCard(provider: provider, message: errorMessage)
            } else if providerSnapshots.isEmpty {
                ProviderEmptyCard(provider: provider)
            } else {
                ForEach(providerSnapshots) { snapshot in
                    ProviderUsageCard(snapshot: snapshot)
                }

                if let errorMessage {
                    ProviderInlineError(message: errorMessage)
                }
            }
        }
    }
}

private struct ProviderUsageCard: View {
    let snapshot: ProviderUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(snapshot.context)
                    .font(.caption.weight(.medium))
                    .foregroundColor(QuotaColors.usageBadgeTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(QuotaColors.usageBadgeTint.opacity(0.10))
                    .clipShape(Capsule())

                Spacer()
            }

            Text(snapshot.primaryLabel)
                .font(.caption)
                .foregroundColor(QuotaColors.secondaryText)
                .padding(.top, 14)

            Text(snapshot.primaryValue)
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .foregroundColor(QuotaColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.top, 2)

            if !snapshot.metrics.isEmpty {
                Divider()
                    .overlay(QuotaColors.separator)
                    .padding(.vertical, 14)

                HStack(spacing: 0) {
                    ForEach(snapshot.metrics.indices, id: \.self) { index in
                        let metric = snapshot.metrics[index]

                        if index > 0 {
                            Rectangle()
                                .fill(QuotaColors.separator)
                                .frame(width: 1, height: 30)
                                .padding(.horizontal, 10)
                        }

                        ProviderMetricView(metric: metric)
                    }
                }
            }

            Text("更新于 \(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(QuotaColors.tertiaryText)
                .padding(.top, 13)
        }
        .padding(16)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    snapshot.isWarning ? QuotaColors.danger : Color.primary.opacity(0.08),
                    lineWidth: snapshot.isWarning ? 2 : 1
                )
        )
    }
}

private struct ProviderMetricView: View {
    let metric: ProviderMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label)
                .font(.caption2)
                .foregroundColor(QuotaColors.secondaryText)

            Text(metric.value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(QuotaColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyProvidersCard: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "switch.2")
                .font(.system(size: 23, weight: .medium))
                .foregroundColor(QuotaColors.primaryText)
                .frame(width: 46, height: 46)
                .background(QuotaColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text("没有启用的厂商")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(QuotaColors.primaryText)

                Text("先在 Settings 中完成配置并启用，Usage 才会显示 API 或 Codex 额度。")
                    .font(.subheadline)
                    .foregroundColor(QuotaColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: openSettings) {
                Label("前往 Settings", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder())
    }
}

private struct ProviderLoadingCard: View {
    let provider: ProviderID

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(QuotaColors.primaryText)

            Text("正在获取 \(provider.displayName) usage")
                .font(.subheadline)
                .foregroundColor(QuotaColors.secondaryText)

            Spacer()
        }
        .padding(16)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder())
    }
}

private struct ProviderEmptyCard: View {
    let provider: ProviderID

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(QuotaColors.secondaryText)

            Text("\(provider.displayName) 暂未返回数据。")
                .font(.caption)
                .foregroundColor(QuotaColors.secondaryText)

            Spacer()
        }
        .padding(16)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(cardBorder())
    }
}

private struct ProviderErrorCard: View {
    let provider: ProviderID
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(QuotaColors.danger)

                Text("\(provider.displayName) 获取失败")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(QuotaColors.primaryText)
            }

            Text(message)
                .font(.caption)
                .foregroundColor(QuotaColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(QuotaColors.danger.opacity(0.65), lineWidth: 1.5)
        )
    }
}

private struct ProviderInlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(QuotaColors.danger)

            Text(message)
                .font(.caption)
                .foregroundColor(QuotaColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(QuotaColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RefreshFeedback {
    let id = UUID()

    enum Kind: Equatable {
        case success
        case failure
        case neutral
    }

    let kind: Kind
    let message: String
}

private struct RefreshFeedbackBanner: View {
    let feedback: RefreshFeedback

    private var iconName: String {
        switch feedback.kind {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.octagon.fill"
        case .neutral:
            return "info.circle"
        }
    }

    private var iconColor: Color {
        feedback.kind == .failure ? QuotaColors.danger : QuotaColors.primaryText
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)

            Text(feedback.message)
                .font(.caption.weight(.medium))
                .foregroundColor(QuotaColors.primaryText)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(QuotaColors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    feedback.kind == .failure
                        ? QuotaColors.danger.opacity(0.7)
                        : Color.primary.opacity(0.08),
                    lineWidth: feedback.kind == .failure ? 1.5 : 1
                )
        )
    }
}

func cardBorder() -> some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Color(uiColor: .systemBackground))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(QuotaColors.primaryText.opacity(configuration.isPressed ? 0.76 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
