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

    func test_batchComposerIsAnInspectorDestination() {
        let selection = RecordingsInspectorSelection.batchComposer

        XCTAssertNil(selection.parentBatchID)
        XCTAssertNil(selection.backDestination)
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

final class RecordingStatisticsTests: XCTestCase {
    func test_usageDurationsPartitionEveryRecordingExactlyOnce() {
        let recordings = [
            makeRecording(type: .voice, duration: 10),
            makeRecording(type: .translation, duration: 20),
            makeRecording(type: .meeting, duration: 30),
            makeRecording(type: .meetingTranslation, duration: 40),
            makeRecording(type: .fileTranscription, duration: 50),
            makeRecording(type: .fileTranscription, duration: 60, remoteSource: makeYouTubeSource())
        ]

        let statistics = RecordingStatistics(recordings: recordings)

        XCTAssertEqual(statistics.voiceDurationSeconds, 10)
        XCTAssertEqual(statistics.translationDurationSeconds, 20)
        XCTAssertEqual(statistics.meetingDurationSeconds, 70)
        XCTAssertEqual(statistics.importedFileDurationSeconds, 50)
        XCTAssertEqual(statistics.youtubeDurationSeconds, 60)
        XCTAssertEqual(statistics.totalDurationSeconds, 210)
        XCTAssertEqual(
            statistics.voiceDurationSeconds
                + statistics.translationDurationSeconds
                + statistics.meetingDurationSeconds
                + statistics.importedFileDurationSeconds
                + statistics.youtubeDurationSeconds,
            statistics.totalDurationSeconds
        )
    }

    func test_timeSavedPreservesTypingMathAndAddsOnlyReadableMediaDuration() {
        let voice = makeRecording(
            type: .voice,
            duration: 60,
            transcriptionText: words(count: 100)
        )
        let readableFile = makeRecording(
            type: .fileTranscription,
            duration: 300,
            status: .failed,
            transcriptionText: "Readable media transcript"
        )
        let unreadableYouTube = makeRecording(
            type: .fileTranscription,
            duration: 400,
            status: .transcribed,
            transcriptionText: " \n\t ",
            remoteSource: makeYouTubeSource()
        )
        let statistics = RecordingStatistics(recordings: [voice, readableFile, unreadableYouTube])

        XCTAssertEqual(
            RecordingStatistics(recordings: [voice]).typingTimeSavedSeconds(wordsPerMinute: 50),
            60
        )
        XCTAssertEqual(statistics.typingTimeSavedSeconds(wordsPerMinute: 50), 60)
        XCTAssertEqual(statistics.mediaTimeSavedSeconds, 300)
        XCTAssertEqual(statistics.totalTimeSavedSeconds(wordsPerMinute: 50), 360)
        XCTAssertEqual(statistics.transcribedWordCount, 103)
    }

    private func makeRecording(
        type: Recording.RecordingType,
        duration: TimeInterval,
        status: Recording.ProcessingStatus = .transcribed,
        transcriptionText: String? = "Transcript",
        remoteSource: RemoteMediaSourceMetadata? = nil
    ) -> Recording {
        Recording(
            id: UUID(),
            createdAt: Date(),
            type: type,
            audioFileName: "recording.m4a",
            durationSeconds: duration,
            fileSizeBytes: 42,
            status: status,
            transcriptionText: transcriptionText,
            sourceDevice: nil,
            remoteSource: remoteSource
        )
    }

    private func words(count: Int) -> String {
        Array(repeating: "word", count: count).joined(separator: " ")
    }

    private func makeYouTubeSource() -> RemoteMediaSourceMetadata {
        RemoteMediaSourceMetadata(
            provider: YouTubeRemoteMediaSource.provider,
            mediaID: "video-id",
            canonicalURL: URL(string: "https://www.youtube.com/watch?v=video-id")!,
            title: "Video",
            channelName: "Channel"
        )
    }
}
