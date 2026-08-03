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
}
