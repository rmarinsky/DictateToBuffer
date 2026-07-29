@testable import Diduny
import XCTest

final class BillingServiceTests: XCTestCase {
    func testBillingStatusDecodesProActiveState() throws {
        let json = """
        {
          "plan": "pro",
          "entitlement": "paid",
          "status": "active",
          "renewsAt": "2026-08-14T00:00:00.000Z",
          "activeUntil": "2026-08-14T00:00:00.000Z",
          "cancelAtPeriodEnd": false,
          "pendingOrderReference": null,
          "usage": {
            "isWhitelisted": false,
            "isUnlimited": true,
            "entitlement": "paid",
            "usedHours": 3.8,
            "limitHours": null,
            "remainingHours": null,
            "usedMs": 13680000,
            "limitMs": null,
            "remainingMs": null
          }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(BillingStatusResponse.self, from: json)

        XCTAssertEqual(status.plan, .pro)
        XCTAssertEqual(status.entitlement, .paid)
        XCTAssertEqual(status.status, .active)
        XCTAssertTrue(status.hasUnlimitedAccess)
        XCTAssertEqual(status.usage?.entitlement, "paid")
        XCTAssertEqual(status.usage?.isUnlimited, true)
    }

    func testBillingStatusDecodesCancelledAndGrantStates() throws {
        let cancelled = """
        {
          "plan": "pro",
          "entitlement": "paid",
          "status": "cancelled",
          "renewsAt": null,
          "activeUntil": "2026-08-14T00:00:00.000Z",
          "cancelAtPeriodEnd": true,
          "pendingOrderReference": null,
          "usage": null
        }
        """.data(using: .utf8)!
        let grant = """
        {
          "plan": "pro",
          "entitlement": "grant",
          "status": "active",
          "renewsAt": null,
          "activeUntil": null,
          "cancelAtPeriodEnd": false,
          "pendingOrderReference": null,
          "usage": null
        }
        """.data(using: .utf8)!

        let cancelledStatus = try JSONDecoder().decode(BillingStatusResponse.self, from: cancelled)
        let grantStatus = try JSONDecoder().decode(BillingStatusResponse.self, from: grant)

        XCTAssertEqual(cancelledStatus.status, .cancelled)
        XCTAssertTrue(cancelledStatus.cancelAtPeriodEnd)
        XCTAssertEqual(grantStatus.entitlement, .grant)
        XCTAssertTrue(grantStatus.hasUnlimitedAccess)
    }
}
