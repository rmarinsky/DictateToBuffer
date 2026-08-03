import XCTest
@testable import Diduny

final class ReleaseHighlightsTests: XCTestCase {
    func testDecodePreservesCuratedHighlightOrder() throws {
        let data = Data(
            #"{"schemaVersion":1,"headline":"A clearer update","highlights":["First","Second","Third"]}"#.utf8
        )

        let highlights = try JSONDecoder().decode(ReleaseHighlights.self, from: data)

        XCTAssertEqual(highlights.schemaVersion, 1)
        XCTAssertEqual(highlights.headline, "A clearer update")
        XCTAssertEqual(highlights.highlights, ["First", "Second", "Third"])
    }

    func testDecodeRejectsUnsupportedOrEmptyPayloads() {
        let invalidPayloads = [
            #"{"schemaVersion":2,"headline":"Headline","highlights":["One"]}"#,
            #"{"schemaVersion":1,"headline":"   ","highlights":["One"]}"#,
            #"{"schemaVersion":1,"headline":"Headline","highlights":[]}"#,
            #"{"schemaVersion":1,"headline":"Headline","highlights":["One","Two","Three","Four"]}"#,
            #"{"schemaVersion":1,"headline":"Headline","highlights":[" "]}"#,
        ]

        for payload in invalidPayloads {
            XCTAssertThrowsError(
                try JSONDecoder().decode(ReleaseHighlights.self, from: Data(payload.utf8)),
                "Expected payload to be rejected: \(payload)"
            )
        }
    }

    func testLoadHidesMissingAndMalformedContent() throws {
        XCTAssertNil(ReleaseHighlights.load(from: nil))

        let malformedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-highlights-\(UUID().uuidString).json")
        try Data(#"{"schemaVersion":1}"#.utf8).write(to: malformedURL)
        defer { try? FileManager.default.removeItem(at: malformedURL) }

        XCTAssertNil(ReleaseHighlights.load(from: malformedURL))
    }

    func testBundledPayloadMatchesCuratedReleaseCopy() throws {
        let highlights = try XCTUnwrap(ReleaseHighlights.bundled())

        XCTAssertEqual(highlights.headline, "A clearer update and a faster first run")
        XCTAssertEqual(
            highlights.highlights,
            [
                "See what changed before an update installs and after Diduny relaunches.",
                "Set up cloud dictation from Overview and try your first phrase immediately.",
                "Grant auto-paste and meeting permissions only when you need them.",
            ]
        )
    }
}

@MainActor
final class UpdateArrivalStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "UpdateArrivalStateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFreshInstallRecordsVersionWithoutPendingNotice() {
        let state = UpdateArrivalState(defaults: defaults)

        state.recordLaunch(version: "2.1.0", isFreshInstall: true)

        XCTAssertEqual(state.highestLaunchedVersion, "2.1.0")
        XCTAssertNil(state.pendingReleaseLine)
    }

    func testNewMajorMinorLineCreatesPersistentPendingNotice() {
        defaults.set("2.1.4", forKey: UpdateArrivalState.highestLaunchedVersionKey)
        let state = UpdateArrivalState(defaults: defaults)

        state.recordLaunch(version: "2.2.0", isFreshInstall: false)

        XCTAssertEqual(state.highestLaunchedVersion, "2.2.0")
        XCTAssertEqual(state.pendingReleaseLine, "2.2")
        XCTAssertEqual(UpdateArrivalState(defaults: defaults).pendingReleaseLine, "2.2")
    }
}
