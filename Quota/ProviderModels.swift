import Foundation

enum ProviderKind: String {
    case balance
    case cost
    case manual
}

enum ProviderFieldKey: String, Hashable {
    case apiKey
    case managementKey
    case teamID
    case adminKey
}

enum ProviderKeyboard: Equatable {
    case ascii
    case url
}

struct ProviderFieldDefinition: Identifiable {
    let key: ProviderFieldKey
    let label: String
    let placeholder: String
    let isSecret: Bool
    let keyboard: ProviderKeyboard

    var id: ProviderFieldKey { key }
}

enum ProviderID: String, CaseIterable, Identifiable, Codable {
    case deepseek
    case moonshot
    case openrouter
    case xai
    case openai
    case anthropic
    case gemini
    case qwen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek:
            return "DeepSeek"
        case .moonshot:
            return "Kimi / Moonshot"
        case .openrouter:
            return "OpenRouter"
        case .xai:
            return "xAI / Grok"
        case .openai:
            return "OpenAI"
        case .anthropic:
            return "Anthropic / Claude"
        case .gemini:
            return "Google Gemini"
        case .qwen:
            return "Qwen / 通义千问"
        }
    }

    var subtitle: String {
        switch self {
        case .deepseek:
            return "API balance"
        case .moonshot:
            return "Open platform balance"
        case .openrouter:
            return "Credits"
        case .xai:
            return "Prepaid balance"
        case .openai:
            return "Organization cost"
        case .anthropic:
            return "Organization cost"
        case .gemini:
            return "AI Studio console"
        case .qwen:
            return "Console only"
        }
    }

    var iconName: String {
        switch self {
        case .deepseek:
            return "waveform.path.ecg"
        case .moonshot:
            return "moon.stars"
        case .openrouter:
            return "arrow.triangle.branch"
        case .xai:
            return "xmark.circle"
        case .openai:
            return "circle.hexagongrid"
        case .anthropic:
            return "a.circle"
        case .gemini:
            return "sparkles"
        case .qwen:
            return "cloud"
        }
    }

    var logoAssetName: String {
        switch self {
        case .deepseek:
            return "ProviderDeepSeek"
        case .moonshot:
            return "ProviderKimi"
        case .openrouter:
            return "ProviderOpenRouter"
        case .xai:
            return "ProviderXAI"
        case .openai:
            return "ProviderOpenAI"
        case .anthropic:
            return "ProviderAnthropic"
        case .gemini:
            return "ProviderGemini"
        case .qwen:
            return "ProviderQwen"
        }
    }

    var kind: ProviderKind {
        switch self {
        case .deepseek, .moonshot, .openrouter, .xai:
            return .balance
        case .openai, .anthropic:
            return .cost
        case .gemini, .qwen:
            return .manual
        }
    }

    var fields: [ProviderFieldDefinition] {
        switch self {
        case .deepseek:
            return [
                ProviderFieldDefinition(
                    key: .apiKey,
                    label: "DeepSeek API Key",
                    placeholder: "sk-...",
                    isSecret: true,
                    keyboard: .ascii
                )
            ]
        case .moonshot:
            return [
                ProviderFieldDefinition(
                    key: .apiKey,
                    label: "Moonshot API Key",
                    placeholder: "sk-...",
                    isSecret: true,
                    keyboard: .ascii
                )
            ]
        case .openrouter:
            return [
                ProviderFieldDefinition(
                    key: .managementKey,
                    label: "OpenRouter Management Key",
                    placeholder: "sk-or-v1-...",
                    isSecret: true,
                    keyboard: .ascii
                )
            ]
        case .xai:
            return [
                ProviderFieldDefinition(
                    key: .managementKey,
                    label: "xAI Management Key",
                    placeholder: "Management Key",
                    isSecret: true,
                    keyboard: .ascii
                ),
                ProviderFieldDefinition(
                    key: .teamID,
                    label: "Team ID",
                    placeholder: "Team UUID",
                    isSecret: false,
                    keyboard: .ascii
                )
            ]
        case .openai:
            return [
                ProviderFieldDefinition(
                    key: .adminKey,
                    label: "OpenAI Admin API Key",
                    placeholder: "Organization Admin Key",
                    isSecret: true,
                    keyboard: .ascii
                )
            ]
        case .anthropic:
            return [
                ProviderFieldDefinition(
                    key: .adminKey,
                    label: "Anthropic Admin API Key",
                    placeholder: "sk-ant-admin01-...",
                    isSecret: true,
                    keyboard: .ascii
                )
            ]
        case .gemini, .qwen:
            return []
        }
    }

    var configurationHint: String {
        switch self {
        case .deepseek:
            return "使用 DeepSeek 官方余额接口，显示总余额、赠送余额和充值余额。"
        case .moonshot:
            return "使用 Kimi / Moonshot 开放平台 API Key。不是 sk-kimi- 开头的登录或订阅凭据。"
        case .openrouter:
            return "Credits API 需要 OpenRouter Management Key，普通推理 Key 无权访问。"
        case .xai:
            return "需要 xAI Management Key 和 Team ID。不能使用普通 xAI 推理 API Key。"
        case .openai:
            return "使用组织级 Costs API，需要 OpenAI Organization Admin Key，显示本月组织用量。"
        case .anthropic:
            return "使用组织级 Cost Report API，需要 Anthropic Admin API Key，显示本月组织用量。"
        case .gemini:
            return "Gemini API 没有可通过普通 API Key 查询预付余额的公开接口。请在 AI Studio Billing 查看预付额度，在 Rate Limit 页面查看用量限制。"
        case .qwen:
            return "阿里云百炼当前没有可通过普通 DashScope API Key 查询通用余额的公开接口，请在百炼控制台查看。"
        }
    }

    var consoleURL: URL? {
        switch self {
        case .deepseek:
            return URL(string: "https://platform.deepseek.com")
        case .moonshot:
            return URL(string: "https://platform.moonshot.cn")
        case .openrouter:
            return URL(string: "https://openrouter.ai/settings/credits")
        case .xai:
            return URL(string: "https://console.x.ai")
        case .openai:
            return URL(string: "https://platform.openai.com/settings/organization/billing")
        case .anthropic:
            return URL(string: "https://platform.claude.com/settings/billing")
        case .gemini:
            return URL(string: "https://aistudio.google.com/billing")
        case .qwen:
            return URL(string: "https://bailian.console.aliyun.com")
        }
    }
}

struct ProviderMetric: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

struct ProviderUsageSnapshot: Identifiable {
    let id: String
    let provider: ProviderID
    let context: String
    let primaryLabel: String
    let primaryValue: String
    let metrics: [ProviderMetric]
    let updatedAt: Date
    let isWarning: Bool
}

struct ProviderRefreshResult {
    let successfulProviders: Int
    let failedProviders: [ProviderID]
    let cancelledProviders: [ProviderID]
}

enum ProviderStoreError: LocalizedError {
    case providerNotConfigurable
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .providerNotConfigurable:
            return "该厂商没有可供应用查询的公开额度接口。"
        case .missingConfiguration:
            return "请先完成该厂商的必填配置。"
        }
    }
}

enum ProviderAmountFormatter {
    static func currency(_ value: Double, code: String) -> String {
        let normalizedCode = code.uppercased()
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true

        let number = NSNumber(value: value)
        let formatted = formatter.string(from: number) ?? String(format: "%.2f", value)
        let negative = formatted.hasPrefix("-")
        let unsigned = negative ? String(formatted.dropFirst()) : formatted
        let symbol: String

        switch normalizedCode {
        case "CNY":
            symbol = "¥"
        case "USD":
            symbol = "$"
        default:
            symbol = ""
        }

        let amount = symbol.isEmpty
            ? "\(unsigned) \(normalizedCode)"
            : "\(symbol)\(unsigned)"
        return negative ? "-\(amount)" : amount
    }

    static func stringCurrency(_ rawValue: String, code: String) -> String {
        let normalized = rawValue.replacingOccurrences(of: ",", with: ".")
        return currency(Double(normalized) ?? 0, code: code)
    }

    static func centsCurrency(_ rawValue: String, code: String) -> String {
        let normalized = rawValue.replacingOccurrences(of: ",", with: ".")
        return currency((Double(normalized) ?? 0) / 100, code: code)
    }
}

struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = Double(value)
        } else if let value = try? container.decode(String.self) {
            self.value = Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
        } else {
            self.value = 0
        }
    }
}
