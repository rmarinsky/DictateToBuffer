import Foundation
import os

@Observable
@MainActor
final class UsageService {
    static let shared = UsageService()

    private(set) var cachedUsage: UsageResponse?
    private(set) var isLoading = false
    private(set) var lastFetched: Date?

    private init() {}

    var formattedRemaining: String {
        guard let usage = cachedUsage else { return "—" }
        if usage.isUnlimited { return "Unlimited" }
        guard let remaining = usage.remainingHours else { return "—" }
        return String(format: "%.1fh remaining", remaining)
    }

    var usagePercent: Double {
        guard let usage = cachedUsage, !usage.isUnlimited,
              let limitMs = usage.limitMs, limitMs > 0
        else { return 0 }
        return Double(usage.usedMs) / Double(limitMs)
    }

    func refresh() async {
        let proxyBase = SettingsStorage.shared.proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(proxyBase)/api/v1/usage/me") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, httpResponse) = try await AuthService.shared.performWithAuth(request)
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                Log.app.warning("[Usage] Failed to fetch usage: HTTP \(httpResponse.statusCode)")
                return
            }
            cachedUsage = try JSONDecoder().decode(UsageResponse.self, from: data)
            lastFetched = Date()
            Log.app.info("[Usage] Refreshed: \(self.formattedRemaining)")
        } catch {
            Log.app.warning("[Usage] Failed to fetch usage: \(error.localizedDescription)")
        }
    }
}

struct UsageResponse: Decodable {
    let isWhitelisted: Bool
    let isUnlimited: Bool
    let entitlement: String?
    let usedHours: Double
    let limitHours: Double?
    let remainingHours: Double?
    let usedMs: Int
    let limitMs: Int?
    let remainingMs: Int?

    enum CodingKeys: String, CodingKey {
        case isWhitelisted
        case isUnlimited
        case entitlement
        case usedHours
        case limitHours
        case remainingHours
        case usedMs
        case limitMs
        case remainingMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isWhitelisted = try container.decode(Bool.self, forKey: .isWhitelisted)
        isUnlimited = try container.decodeIfPresent(Bool.self, forKey: .isUnlimited) ?? isWhitelisted
        entitlement = try container.decodeIfPresent(String.self, forKey: .entitlement)
        usedHours = try container.decode(Double.self, forKey: .usedHours)
        limitHours = try container.decodeIfPresent(Double.self, forKey: .limitHours)
        remainingHours = try container.decodeIfPresent(Double.self, forKey: .remainingHours)
        usedMs = try container.decode(Int.self, forKey: .usedMs)
        limitMs = try container.decodeIfPresent(Int.self, forKey: .limitMs)
        remainingMs = try container.decodeIfPresent(Int.self, forKey: .remainingMs)
    }
}

struct UsageLimitErrorResponse: Decodable {
    let error: String
    let usedHours: Double
    let limitHours: Double
}
