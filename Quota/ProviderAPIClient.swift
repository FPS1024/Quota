import Foundation

enum ProviderAPIError: LocalizedError {
    case invalidURL(ProviderID)
    case invalidResponse(ProviderID)
    case unauthorized(ProviderID)
    case server(ProviderID, statusCode: Int, message: String?)
    case decoding(ProviderID)
    case providerMessage(ProviderID, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let provider):
            return "\(provider.displayName) 接口地址无效。"
        case .invalidResponse(let provider):
            return "\(provider.displayName) 返回了无法识别的响应。"
        case .unauthorized(let provider):
            return "\(provider.displayName) 凭据无效或没有查询权限。"
        case .server(let provider, let statusCode, let message):
            if let message, !message.isEmpty {
                return "\(provider.displayName) 请求失败（\(statusCode)）：\(message)"
            }
            return "\(provider.displayName) 请求失败，状态码：\(statusCode)。"
        case .decoding(let provider):
            return "\(provider.displayName) 返回的数据格式无法解析。"
        case .providerMessage(let provider, let message):
            return "\(provider.displayName)：\(message)"
        }
    }
}

final class ProviderAPIClient {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(
        provider: ProviderID,
        credentials: [ProviderFieldKey: String]
    ) async throws -> [ProviderUsageSnapshot] {
        switch provider {
        case .deepseek:
            return try await fetchDeepSeek(credentials: credentials)
        case .moonshot:
            return try await fetchMoonshot(credentials: credentials)
        case .openrouter:
            return try await fetchOpenRouter(credentials: credentials)
        case .xai:
            return try await fetchXAI(credentials: credentials)
        case .openai:
            return try await fetchOpenAI(credentials: credentials)
        case .anthropic:
            return try await fetchAnthropic(credentials: credentials)
        case .gemini, .qwen:
            throw ProviderAPIError.providerMessage(
                provider,
                "暂无可通过普通 API Key 查询余额的公开接口。"
            )
        }
    }

    private func fetchDeepSeek(
        credentials: [ProviderFieldKey: String]
    ) async throws -> [ProviderUsageSnapshot] {
        let apiKey = try credential(.apiKey, from: credentials, provider: .deepseek)
        var request = URLRequest(url: try url("https://api.deepseek.com/user/balance", provider: .deepseek))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data = try await data(for: request, provider: .deepseek)
        let response: DeepSeekBalanceResponse

        do {
            response = try decoder.decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(.deepseek)
        }

        return response.balanceInfos.map { info in
            let total = amountValue(info.totalBalance)
            let granted = amountValue(info.grantedBalance)
            let toppedUp = amountValue(info.toppedUpBalance)
            let currency = info.currency.uppercased()

            return ProviderUsageSnapshot(
                id: "deepseek.\(currency.lowercased())",
                provider: .deepseek,
                context: "\(currency) · \(currencyDisplayName(currency))",
                primaryLabel: "总余额（剩余可用）",
                primaryValue: ProviderAmountFormatter.stringCurrency(info.totalBalance, code: currency),
                metrics: [
                    ProviderMetric(
                        label: "赠送余额",
                        value: ProviderAmountFormatter.stringCurrency(info.grantedBalance, code: currency)
                    ),
                    ProviderMetric(
                        label: "充值余额",
                        value: ProviderAmountFormatter.stringCurrency(info.toppedUpBalance, code: currency)
                    )
                ],
                updatedAt: Date(),
                isWarning: !response.isAvailable || total < 0 || granted < 0 || toppedUp < 0
            )
        }
    }

    private func fetchMoonshot(
        credentials: [ProviderFieldKey: String]
    ) async throws -> [ProviderUsageSnapshot] {
        let apiKey = try credential(.apiKey, from: credentials, provider: .moonshot)
        var request = URLRequest(
            url: try url("https://api.moonshot.cn/v1/users/me/balance", provider: .moonshot)
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data = try await data(for: request, provider: .moonshot)
        let response: MoonshotBalanceResponse

        do {
            response = try decoder.decode(MoonshotBalanceResponse.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(.moonshot)
        }

        if let code = response.code, code != 0 {
            throw ProviderAPIError.providerMessage(.moonshot, response.message ?? "请求失败（\(code)）")
        }

        guard let balance = response.data else {
            throw ProviderAPIError.decoding(.moonshot)
        }

        let currency = (balance.currency ?? "CNY").uppercased()
        let available = balance.availableBalance.value
        let voucher = balance.voucherBalance.value
        let cash = balance.cashBalance.value

        return [
            ProviderUsageSnapshot(
                id: "moonshot.\(currency.lowercased())",
                provider: .moonshot,
                context: "\(currency) · 人民币",
                primaryLabel: "剩余可用余额",
                primaryValue: ProviderAmountFormatter.currency(available, code: currency),
                metrics: [
                    ProviderMetric(
                        label: "代金券余额",
                        value: ProviderAmountFormatter.currency(voucher, code: currency)
                    ),
                    ProviderMetric(
                        label: "现金余额",
                        value: ProviderAmountFormatter.currency(cash, code: currency)
                    )
                ],
                updatedAt: Date(),
                isWarning: available < 0 || voucher < 0 || cash < 0
            )
        ]
    }

    private func fetchOpenRouter(
        credentials: [ProviderFieldKey: String]
    ) async throws -> [ProviderUsageSnapshot] {
        let managementKey = try credential(
            .managementKey,
            from: credentials,
            provider: .openrouter
        )
        var request = URLRequest(
            url: try url("https://openrouter.ai/api/v1/credits", provider: .openrouter)
        )
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")

        let data = try await data(for: request, provider: .openrouter)
        let response: OpenRouterCreditsResponse

        do {
            response = try decoder.decode(OpenRouterCreditsResponse.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(.openrouter)
        }

        let totalCredits = response.data.totalCredits.value
        let totalUsage = response.data.totalUsage.value
        let remaining = totalCredits - totalUsage

        return [
            ProviderUsageSnapshot(
                id: "openrouter.usd",
                provider: .openrouter,
                context: "USD · Credits",
                primaryLabel: "剩余余额",
                primaryValue: ProviderAmountFormatter.currency(remaining, code: "USD"),
                metrics: [
                    ProviderMetric(
                        label: "总 Credits",
                        value: ProviderAmountFormatter.currency(totalCredits, code: "USD")
                    ),
                    ProviderMetric(
                        label: "已用",
                        value: ProviderAmountFormatter.currency(totalUsage, code: "USD")
                    )
                ],
                updatedAt: Date(),
                isWarning: remaining < 0
            )
        ]
    }

    private func fetchXAI(
        credentials: [ProviderFieldKey: String]
    ) async throws -> [ProviderUsageSnapshot] {
        let managementKey = try credential(
            .managementKey,
            from: credentials,
            provider: .xai
        )
        let teamID = try credential(.teamID, from: credentials, provider: .xai)
        var components = URLComponents(string: "https://management-api.x.ai")
        components?.path = "/v1/billing/teams/\(teamID)/prepaid/balance"

        guard let url = components?.url else {
            throw ProviderAPIError.invalidURL(.xai)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")

        let data = try await data(for: request, provider: .xai)
        let response: XAIPrepaidBalanceResponse

        do {
            response = try decoder.decode(XAIPrepaidBalanceResponse.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(.xai)
        }

        let signedCents = Double(
            response.total.val.replacingOccurrences(of: ",", with: ".")
        ) ?? 0
        let balanceUSD = abs(signedCents) / 100

        return [
            ProviderUsageSnapshot(
                id: "xai.usd",
                provider: .xai,
                context: "USD · Prepaid Credits",
                primaryLabel: "预付余额",
                primaryValue: ProviderAmountFormatter.currency(balanceUSD, code: "USD"),
                metrics: [
                    ProviderMetric(label: "余额单位", value: "USD"),
                    ProviderMetric(
                        label: "状态",
                        value: balanceUSD > 0 ? "可用" : "已用尽"
                    )
                ],
                updatedAt: Date(),
                isWarning: balanceUSD <= 0
            )
        ]
    }

    private func fetchOpenAI(
        credentials: [ProviderFieldKey: String]
    ) async throws -> [ProviderUsageSnapshot] {
        let adminKey = try credential(.adminKey, from: credentials, provider: .openai)
        let start = startOfCurrentMonthUTC()
        var components = URLComponents(string: "https://api.openai.com/v1/organization/costs")
        components?.queryItems = [
            URLQueryItem(
                name: "start_time",
                value: String(Int(start.timeIntervalSince1970))
            ),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]

        guard let url = components?.url else {
            throw ProviderAPIError.invalidURL(.openai)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")

        let data = try await data(for: request, provider: .openai)
        let response: OpenAICostResponse

        do {
            response = try decoder.decode(OpenAICostResponse.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(.openai)
        }

        var totalsByCurrency: [String: Double] = [:]
        for bucket in response.data {
            for result in bucket.results {
                let currency = (result.amount.currency ?? "usd").uppercased()
                totalsByCurrency[currency, default: 0] += result.amount.value.value
            }
        }

        if totalsByCurrency.isEmpty {
            totalsByCurrency["USD"] = 0
        }

        return totalsByCurrency.keys.sorted().map { currency in
            let value = totalsByCurrency[currency] ?? 0
            return ProviderUsageSnapshot(
                id: "openai.\(currency.lowercased())",
                provider: .openai,
                context: "\(currency) · Organization Costs",
                primaryLabel: "本月组织用量",
                primaryValue: ProviderAmountFormatter.currency(value, code: currency),
                metrics: [
                    ProviderMetric(label: "统计范围", value: "本月"),
                    ProviderMetric(label: "数据来源", value: "Costs API")
                ],
                updatedAt: Date(),
                isWarning: false
            )
        }
    }

    private func fetchAnthropic(
        credentials: [ProviderFieldKey: String]
    ) async throws -> [ProviderUsageSnapshot] {
        let adminKey = try credential(.adminKey, from: credentials, provider: .anthropic)
        let start = startOfCurrentMonthUTC()
        var components = URLComponents(
            string: "https://api.anthropic.com/v1/organizations/cost_report"
        )
        components?.queryItems = [
            URLQueryItem(name: "starting_at", value: iso8601String(from: start)),
            URLQueryItem(name: "ending_at", value: iso8601String(from: Date())),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31")
        ]

        guard let url = components?.url else {
            throw ProviderAPIError.invalidURL(.anthropic)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Quota/1.0", forHTTPHeaderField: "User-Agent")

        let data = try await data(for: request, provider: .anthropic)
        let response: AnthropicCostResponse

        do {
            response = try decoder.decode(AnthropicCostResponse.self, from: data)
        } catch {
            throw ProviderAPIError.decoding(.anthropic)
        }

        var totalsByCurrency: [String: Double] = [:]
        for bucket in response.data {
            for result in bucket.results {
                let currency = result.currency.uppercased()
                let cents = Double(
                    result.amount.replacingOccurrences(of: ",", with: ".")
                ) ?? 0
                totalsByCurrency[currency, default: 0] += cents / 100
            }
        }

        if totalsByCurrency.isEmpty {
            totalsByCurrency["USD"] = 0
        }

        return totalsByCurrency.keys.sorted().map { currency in
            let value = totalsByCurrency[currency] ?? 0
            return ProviderUsageSnapshot(
                id: "anthropic.\(currency.lowercased())",
                provider: .anthropic,
                context: "\(currency) · Cost Report",
                primaryLabel: "本月用量",
                primaryValue: ProviderAmountFormatter.currency(value, code: currency),
                metrics: [
                    ProviderMetric(label: "统计范围", value: "本月"),
                    ProviderMetric(label: "数据来源", value: "Admin API")
                ],
                updatedAt: Date(),
                isWarning: false
            )
        }
    }

    private func credential(
        _ field: ProviderFieldKey,
        from credentials: [ProviderFieldKey: String],
        provider: ProviderID
    ) throws -> String {
        guard let value = credentials[field], !value.isEmpty else {
            throw ProviderAPIError.providerMessage(
                provider,
                "缺少 \(field.rawValue) 配置。"
            )
        }
        return value
    }

    private func data(for request: URLRequest, provider: ProviderID) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ProviderAPIError.providerMessage(provider, error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderAPIError.invalidResponse(provider)
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ProviderAPIError.unauthorized(provider)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let envelope = try? decoder.decode(ProviderErrorEnvelope.self, from: data)
            throw ProviderAPIError.server(
                provider,
                statusCode: httpResponse.statusCode,
                message: envelope?.error?.message ?? envelope?.message
            )
        }

        return data
    }

    private func url(_ rawValue: String, provider: ProviderID) throws -> URL {
        guard let url = URL(string: rawValue), let scheme = url.scheme, scheme == "https" else {
            throw ProviderAPIError.invalidURL(provider)
        }
        return url
    }

    private func amountValue(_ rawValue: String) -> Double {
        Double(rawValue.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func currencyDisplayName(_ currency: String) -> String {
        switch currency.uppercased() {
        case "CNY":
            return "人民币"
        case "USD":
            return "美元"
        default:
            return currency
        }
    }

    private func startOfCurrentMonthUTC() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [DeepSeekBalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

private struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

private struct MoonshotBalanceResponse: Decodable {
    let code: Int?
    let data: MoonshotBalanceData?
    let message: String?
}

private struct MoonshotBalanceData: Decodable {
    let availableBalance: FlexibleDouble
    let voucherBalance: FlexibleDouble
    let cashBalance: FlexibleDouble
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case availableBalance = "available_balance"
        case voucherBalance = "voucher_balance"
        case cashBalance = "cash_balance"
        case currency
    }
}

private struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCreditsData
}

private struct OpenRouterCreditsData: Decodable {
    let totalCredits: FlexibleDouble
    let totalUsage: FlexibleDouble

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}

private struct XAIPrepaidBalanceResponse: Decodable {
    let total: XAIAmount
}

private struct XAIAmount: Decodable {
    let val: String
}

private struct OpenAICostResponse: Decodable {
    let data: [OpenAICostBucket]
}

private struct OpenAICostBucket: Decodable {
    let results: [OpenAICostResult]
}

private struct OpenAICostResult: Decodable {
    let amount: OpenAICostAmount
}

private struct OpenAICostAmount: Decodable {
    let value: FlexibleDouble
    let currency: String?
}

private struct AnthropicCostResponse: Decodable {
    let data: [AnthropicCostBucket]
}

private struct AnthropicCostBucket: Decodable {
    let results: [AnthropicCostResult]
}

private struct AnthropicCostResult: Decodable {
    let amount: String
    let currency: String
}

private struct ProviderErrorEnvelope: Decodable {
    let error: ProviderErrorDetail?
    let message: String?
}

private struct ProviderErrorDetail: Decodable {
    let message: String?
}
