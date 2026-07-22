@testable import Diduny
import XCTest

final class RecordingsLibraryFilterTests: XCTestCase {
    func test_filesFilterMatchesOnlyImportedFileTranscriptions() {
        XCTAssertTrue(RecordingsLibraryView.RecordingTypeFilter.files.matches(.fileTranscription))
        XCTAssertFalse(RecordingsLibraryView.RecordingTypeFilter.files.matches(.voice))
        XCTAssertFalse(RecordingsLibraryView.RecordingTypeFilter.files.matches(.meeting))
        XCTAssertFalse(RecordingsLibraryView.RecordingTypeFilter.voiceNotes.matches(.fileTranscription))
    }
}
