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
            updateStatus(try JSONDecoder().decode(BillingStatusResponse.self, from: data))
            Log.app.info("[Billing] Refreshed: \(self.cachedStatus?.status.rawValue ?? "unknown")")
        } catch {
            Log.app.warning("[Billing] Failed to fetch billing: \(error.localizedDescription)")
        }
    }

    func startCheckout() async throws {
        let checkout = try await post(path: "/checkout", body: EmptyBillingBody(), as: BillingCheckoutResponse.self)
        openCheckout(checkout)
    }

    func sync(orderReference: String? = nil) async throws {
        let reference = orderReference ?? SettingsStorage.shared.billingPendingOrderReference
        updateStatus(try await post(
            path: "/sync",
            body: BillingSyncRequest(orderReference: reference),
            as: BillingStatusResponse.self
        ))
    }

    func cancelRenewal() async throws {
        updateStatus(try await post(path: "/cancel", body: EmptyBillingBody(), as: BillingStatusResponse.self))
    }

    /// Within the paid period the backend resumes the suspended WayForPay rule
    /// and returns billing state; after expiry it returns a fresh checkout.
    func resumeRenewal() async throws {
        let data = try await postRaw(path: "/resume", body: EmptyBillingBody())
        if let checkout = try? JSONDecoder().decode(BillingCheckoutResponse.self, from: data) {
            openCheckout(checkout)
            return
        }
        updateStatus(try JSONDecoder().decode(BillingStatusResponse.self, from: data))
    }

    private func openCheckout(_ checkout: BillingCheckoutResponse) {
        SettingsStorage.shared.billingPendingOrderReference = checkout.orderReference
        cachedStatus = BillingStatusResponse.checkoutPending(orderReference: checkout.orderReference)
        guard let url = URL(string: checkout.paymentUrl) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func updateStatus(_ status: BillingStatusResponse) {
        cachedStatus = status
        lastFetched = Date()
        // A checkout survives app restarts only through this stored reference;
        // any settled state clears it.
        if status.status != .checkoutPending {
            SettingsStorage.shared.billingPendingOrderReference = nil
        }
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        as responseType: Response.Type
    ) async throws -> Response {
        try JSONDecoder().decode(responseType, from: try await postRaw(path: path, body: body))
    }

    private func postRaw<Body: Encodable>(path: String, body: Body) async throws -> Data {
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
        return data
    }
}

// Billing enums decode unknown backend values into `.unknown` instead of
// failing the whole response — a new lifecycle state on the server must never
// blank the entire billing UI in older app builds.
enum BillingPlan: String, Decodable {
    case free
    case pro
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BillingPlan(rawValue: raw) ?? .unknown
    }
}

enum BillingEntitlement: String, Decodable {
    case free
    case paid
    case grant
    case legacyUnlimited = "legacy_unlimited"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BillingEntitlement(rawValue: raw) ?? .unknown
    }
}

enum BillingStatus: String, Decodable {
    case active
    case checkoutPending = "checkout_pending"
    case cancelled
    case pastDue = "past_due"
    case expired
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BillingStatus(rawValue: raw) ?? .unknown
    }
}

struct BillingPrice: Decodable {
    let amount: Double
    let currency: String

    var formattedMonthly: String {
        let value = amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amount))
            : String(format: "%.2f", amount)
        let symbol = currency == "UAH" ? "₴" : currency
        return "\(value) \(symbol)/month"
    }
}

struct BillingStatusResponse: Decodable {
    let plan: BillingPlan
    let entitlement: BillingEntitlement
    let status: BillingStatus
    let renewsAt: String?
    let activeUntil: String?
    let cancelAtPeriodEnd: Bool
    let pendingOrderReference: String?
    let price: BillingPrice?
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
            price: nil,
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
