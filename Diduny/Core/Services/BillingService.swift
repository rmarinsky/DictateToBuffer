import AppKit
import Foundation

@Observable
@MainActor
final class BillingService {
    static let shared = BillingService()

    private(set) var cachedStatus: BillingStatusResponse?
    private(set) var isLoading = false
    private(set) var lastFetched: Date?

    private init() {}

    var isPro: Bool {
        cachedStatus?.plan == .pro
    }

    var hasVisibleBillingState: Bool {
        cachedStatus != nil || RemoteConfigService.shared.billingEnabled
    }

    func refresh() async {
        let proxyBase = SettingsStorage.shared.proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(proxyBase)/api/v1/billing/me") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, httpResponse) = try await AuthService.shared.performWithAuth(request)
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                Log.app.warning("[Billing] Failed to fetch billing: HTTP \(httpResponse.statusCode)")
                return
            }
            cachedStatus = try JSONDecoder().decode(BillingStatusResponse.self, from: data)
            lastFetched = Date()
            Log.app.info("[Billing] Refreshed: \(self.cachedStatus?.status.rawValue ?? "unknown")")
        } catch {
            Log.app.warning("[Billing] Failed to fetch billing: \(error.localizedDescription)")
        }
    }

    func startCheckout() async throws {
        let checkout = try await post(path: "/checkout", body: EmptyBillingBody(), as: BillingCheckoutResponse.self)
        cachedStatus = BillingStatusResponse.checkoutPending(orderReference: checkout.orderReference)
        guard let url = URL(string: checkout.paymentUrl) else {
            throw BillingError.invalidCheckoutURL
        }
        NSWorkspace.shared.open(url)
    }

    func sync(orderReference: String? = nil) async throws {
        cachedStatus = try await post(
            path: "/sync",
            body: BillingSyncRequest(orderReference: orderReference),
            as: BillingStatusResponse.self
        )
        lastFetched = Date()
    }

    func cancelRenewal() async throws {
        cachedStatus = try await post(path: "/cancel", body: EmptyBillingBody(), as: BillingStatusResponse.self)
        lastFetched = Date()
    }

    func resumeRenewal() async throws {
        try await startCheckout()
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        as responseType: Response.Type
    ) async throws -> Response {
        let proxyBase = SettingsStorage.shared.proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(proxyBase)/api/v1/billing\(path)") else {
            throw BillingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        isLoading = true
        defer { isLoading = false }

        let (data, httpResponse) = try await AuthService.shared.performWithAuth(request)
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(BillingErrorResponse.self, from: data) {
                throw BillingError.server(errorBody.error)
            }
            throw BillingError.server("HTTP \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode(responseType, from: data)
    }
}

enum BillingPlan: String, Decodable {
    case free
    case pro
}

enum BillingEntitlement: String, Decodable {
    case free
    case paid
    case grant
    case legacyUnlimited = "legacy_unlimited"
}

enum BillingStatus: String, Decodable {
    case active
    case checkoutPending = "checkout_pending"
    case cancelled
    case pastDue = "past_due"
    case expired
}

struct BillingStatusResponse: Decodable {
    let plan: BillingPlan
    let entitlement: BillingEntitlement
    let status: BillingStatus
    let renewsAt: String?
    let activeUntil: String?
    let cancelAtPeriodEnd: Bool
    let pendingOrderReference: String?
    let usage: UsageResponse?

    var hasUnlimitedAccess: Bool {
        plan == .pro || entitlement == .paid || entitlement == .grant || entitlement == .legacyUnlimited
    }

    static func checkoutPending(orderReference: String) -> BillingStatusResponse {
        BillingStatusResponse(
            plan: .free,
            entitlement: .free,
            status: .checkoutPending,
            renewsAt: nil,
            activeUntil: nil,
            cancelAtPeriodEnd: false,
            pendingOrderReference: orderReference,
            usage: nil
        )
    }
}

struct BillingCheckoutResponse: Decodable {
    let orderReference: String
    let paymentUrl: String
}

private struct BillingSyncRequest: Encodable {
    let orderReference: String?
}

private struct EmptyBillingBody: Encodable {}

private struct BillingErrorResponse: Decodable {
    let error: String
}

enum BillingError: LocalizedError {
    case invalidURL
    case invalidCheckoutURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid billing URL"
        case .invalidCheckoutURL:
            "Invalid checkout URL"
        case let .server(message):
            message
        }
    }
}
