@testable import Diduny
import XCTest

final class AsyncTranscriptionJobFileUploadTests: XCTestCase {
    func test_fileUploadMetadata_preservesSupportedStoredAudioFormats() {
        XCTAssertEqual(
            AsyncTranscriptionJobService.fileUploadMetadata(
                for: URL(fileURLWithPath: "/tmp/meeting.flac")
            ).contentType,
            "audio/flac"
        )
        XCTAssertEqual(
            AsyncTranscriptionJobService.fileUploadMetadata(
                for: URL(fileURLWithPath: "/tmp/import.m4a")
            ).contentType,
            "audio/mp4"
        )
        XCTAssertEqual(
            AsyncTranscriptionJobService.fileUploadMetadata(
                for: URL(fileURLWithPath: "/tmp/note.mp3")
            ).contentType,
            "audio/mpeg"
        )
    }

    func test_statusPayloadDecodesExactServerProgress() throws {
        let update = try XCTUnwrap(
            AsyncTranscriptionJobService.progressUpdate(
                fromStatusPayload: #"{"status":"processing","progress":42}"#
            )
        )

        XCTAssertEqual(update.status, .processing)
        XCTAssertEqual(try XCTUnwrap(update.fractionCompleted), 0.42, accuracy: 0.001)
    }
}
