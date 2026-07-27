@testable import Diduny
import XCTest

final class RecordingsLibraryFilterTests: XCTestCase {
    func test_filesFilterMatchesOnlyImportedFileTranscriptions() {
        let file = makeRecording(remoteSource: nil)
        let youtube = makeRecording(remoteSource: makeYouTubeSource())

        XCTAssertTrue(RecordingsLibraryView.RecordingTypeFilter.files.matches(file))
        XCTAssertFalse(RecordingsLibraryView.RecordingTypeFilter.files.matches(youtube))
        XCTAssertTrue(RecordingsLibraryView.RecordingTypeFilter.youtube.matches(youtube))
        XCTAssertFalse(RecordingsLibraryView.RecordingTypeFilter.youtube.matches(file))
    }

    func test_youtubeRecordingHasDistinctLibraryPresentation() {
        let recording = makeRecording(remoteSource: makeYouTubeSource())

        XCTAssertEqual(recording.libraryDisplayName, "YouTube Video")
        XCTAssertEqual(recording.libraryIconName, "play.rectangle.fill")
    }

    private func makeRecording(remoteSource: RemoteMediaSourceMetadata?) -> Recording {
        Recording(
            id: UUID(),
            createdAt: Date(),
            type: .fileTranscription,
            audioFileName: "video.m4a",
            durationSeconds: 120,
            fileSizeBytes: 42,
            status: .transcribed,
            transcriptionText: "Transcript",
            sourceDevice: nil,
            sourceFileName: "Video",
            remoteSource: remoteSource
        )
    }

    private func makeYouTubeSource() -> RemoteMediaSourceMetadata {
        RemoteMediaSourceMetadata(
            provider: YouTubeRemoteMediaSource.provider,
            mediaID: "dQw4w9WgXcQ",
            canonicalURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
            title: "Video",
            channelName: "Channel"
        )
    }
}
