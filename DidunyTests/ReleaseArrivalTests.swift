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
}
