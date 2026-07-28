@testable import Diduny
import XCTest

final class RecordingsLibraryFilterTests: XCTestCase {
    @MainActor
    func test_batchComposerActionTargetsRecordingsWithSharedTitle() {
        let controller = MainWindowController.shared
        controller.requestedSection = nil
        controller.requestedBatchComposer = false
        defer {
            controller.requestedSection = nil
            controller.requestedBatchComposer = false
        }

        controller.requestBatchComposer()

        XCTAssertEqual(MainWindowController.batchComposerActionTitle, "Batch Files and URLs…")
        XCTAssertEqual(controller.requestedSection, .recordings)
        XCTAssertTrue(controller.requestedBatchComposer)
    }

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

    func test_hasTranslationMatchesAttachedTranslationArtifact() {
        var recording = makeRecording(remoteSource: nil)
        XCTAssertFalse(RecordingsLibraryView.RecordingTypeFilter.hasTranslation.matches(recording))

        recording.translationTargetLanguageCode = "en"

        XCTAssertTrue(RecordingsLibraryView.RecordingTypeFilter.hasTranslation.matches(recording))
    }

    func test_batchesFilterShowsBatchesInsteadOfIndividualRecordings() {
        let recording = makeRecording(remoteSource: nil)

        XCTAssertTrue(RecordingsLibraryView.RecordingTypeFilter.batches.showsBatches)
        XCTAssertFalse(RecordingsLibraryView.RecordingTypeFilter.batches.matches(recording))
    }

    func test_recordingOpenedFromBatchCanNavigateBackButDirectRecordingCannot() {
        let batchID = UUID()
        let recordingID = UUID()
        let nested = RecordingsInspectorSelection.recording(
            recordingID,
            parentBatchID: batchID
        )
        let direct = RecordingsInspectorSelection.recording(
            recordingID,
            parentBatchID: nil
        )

        XCTAssertEqual(nested.parentBatchID, batchID)
        XCTAssertEqual(nested.backDestination, .batch(batchID))
        XCTAssertNil(direct.parentBatchID)
        XCTAssertNil(direct.backDestination)
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
