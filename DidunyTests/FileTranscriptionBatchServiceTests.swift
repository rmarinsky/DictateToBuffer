@testable import Diduny
import XCTest

@MainActor
final class FileTranscriptionBatchServiceTests: XCTestCase {
    func test_add_skipsDuplicateURLsWithinActiveBatch() {
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let first = URL(fileURLWithPath: "/tmp/first.mov")

        service.add(urls: [first, first, URL(fileURLWithPath: "/tmp/second.mp3")])

        XCTAssertEqual(service.items.map(\.sourceURL), [first, URL(fileURLWithPath: "/tmp/second.mp3")])
    }

    func test_cloudBatchProcessesUpToThreeFilesConcurrentlyAndCompletesOnce() async throws {
        let preparer = BatchTestPreparer()
        let transcriber = BatchTestTranscriber()
        let store = BatchTestRecordingStore()
        var completionSoundCount = 0
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: transcriber,
            recordingStore: store,
            settingsSnapshot: { .testValue },
            playCompletionSound: { completionSoundCount += 1 }
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/first.mov"),
            URL(fileURLWithPath: "/tmp/second.mp4"),
            URL(fileURLWithPath: "/tmp/third.mp4"),
            URL(fileURLWithPath: "/tmp/fourth.mp4")
        ])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 4 }

        XCTAssertEqual(service.items.map(\.status), [.completed, .completed, .completed, .completed])
        XCTAssertEqual(transcriber.maximumConcurrentCount, 3)
        XCTAssertEqual(Set(transcriber.transcribedFileNames), Set(["first.m4a", "second.m4a", "third.m4a", "fourth.m4a"]))
        XCTAssertEqual(completionSoundCount, 1)
    }

    func test_localBatchProcessesOneFileAtATime() async throws {
        let transcriber = BatchTestTranscriber(delay: .milliseconds(80))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .localTestValue },
            playCompletionSound: {}
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/first.mov"),
            URL(fileURLWithPath: "/tmp/second.mp4")
        ])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(transcriber.maximumConcurrentCount, 1)
    }

    func test_add_reusesCompletedImportedRecordingAsDuplicate() {
        let recordingID = UUID()
        let preparer = BatchTestPreparer()
        let transcriber = BatchTestTranscriber()
        let store = BatchTestRecordingStore(
            duplicate: BatchTranscriptionDuplicate(
                recordingID: recordingID,
                transcriptionText: "Existing transcript",
                durationSeconds: 125
            )
        )
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: transcriber,
            recordingStore: store,
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.beginBatch(urls: [URL(fileURLWithPath: "/tmp/already-done.mov")])

        XCTAssertEqual(service.items.first?.status, .duplicate)
        XCTAssertEqual(service.items.first?.recordingID, recordingID)
        XCTAssertEqual(service.items.first?.transcriptionText, "Existing transcript")
        XCTAssertEqual(service.items.first?.durationSeconds, 125)
        XCTAssertTrue(preparer.preparedSourceNames.isEmpty)
        XCTAssertTrue(transcriber.transcribedFileNames.isEmpty)
        XCTAssertFalse(service.isProcessing)
    }

    func test_failedFileDoesNotStopRemainingBatch() async throws {
        let preparer = BatchTestPreparer(failingSourceNames: ["broken.mov"])
        let transcriber = BatchTestTranscriber()
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/broken.mov"),
            URL(fileURLWithPath: "/tmp/valid.mov")
        ])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(service.items[0].status, .failed)
        XCTAssertEqual(service.items[1].status, .completed)
        XCTAssertEqual(service.failedCount, 1)
        XCTAssertEqual(service.completedCount, 1)
    }

    func test_cancelAllCancelsCurrentAndPendingItems() async throws {
        let transcriber = BatchTestTranscriber(delay: .seconds(10))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [
            URL(fileURLWithPath: "/tmp/first.mov"),
            URL(fileURLWithPath: "/tmp/second.mov")
        ])
        service.startIfNeeded()
        try await waitUntil { service.items.first?.status == .uploading }
        service.cancelAll()
        try await waitUntil { !service.isProcessing }

        XCTAssertEqual(service.items.map(\.status), [.cancelled, .cancelled])
    }

    func test_preflightFailureDoesNotStartAudioPreparation() {
        let preparer = BatchTestPreparer()
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: BatchTestTranscriber(preflightError: "Download a model first."),
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        service.startIfNeeded()

        XCTAssertEqual(service.batchError, "Download a model first.")
        XCTAssertFalse(service.isProcessing)
        XCTAssertTrue(preparer.preparedSourceNames.isEmpty)
        XCTAssertEqual(service.items.first?.status, .queued)
    }

    func test_addWhileProcessingAppendsToTheRunningBatch() async throws {
        let transcriber = BatchTestTranscriber(delay: .milliseconds(250))
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        service.startIfNeeded()
        try await waitUntil { service.items.first?.status == .uploading }
        service.add(urls: [URL(fileURLWithPath: "/tmp/second.mov")])
        service.startIfNeeded()
        try await waitUntil { transcriber.maximumConcurrentCount == 2 }
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(Set(transcriber.transcribedFileNames), Set(["first.m4a", "second.m4a"]))
        XCTAssertEqual(service.items.map(\.status), [.completed, .completed])
    }

    func test_addAfterProcessingAppendsWithoutClearingFinishedRows() async throws {
        let transcriber = BatchTestTranscriber()
        var completionSoundCount = 0
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: { completionSoundCount += 1 }
        )

        service.beginBatch(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        try await waitUntil { !service.isProcessing && service.completedCount == 1 }
        service.add(urls: [URL(fileURLWithPath: "/tmp/second.mov")])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.completedCount == 2 }

        XCTAssertEqual(service.items.map(\.sourceURL.lastPathComponent), ["first.mov", "second.mov"])
        XCTAssertEqual(service.items.map(\.status), [.completed, .completed])
        XCTAssertEqual(completionSoundCount, 1)
    }

    func test_completedItemRemovesTemporaryPreparedAudio() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyBatchTests-\(UUID().uuidString)")
        let preparer = BatchTestPreparer(outputDirectory: outputDirectory)
        let service = FileTranscriptionBatchService(
            preparer: preparer,
            transcriber: BatchTestTranscriber(),
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.add(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 1 }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("first.m4a").path))
        try? FileManager.default.removeItem(at: outputDirectory)
    }

    func test_retryUsesInitialSettingsSnapshotAndPlaysSoundOnlyOnce() async throws {
        var snapshot = FileTranscriptionSettingsSnapshot.testValue
        let transcriber = BatchTestTranscriber(failureCount: 1)
        var completionSoundCount = 0
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { snapshot },
            playCompletionSound: { completionSoundCount += 1 }
        )

        service.beginBatch(urls: [URL(fileURLWithPath: "/tmp/first.mov")])
        try await waitUntil { !service.isProcessing && service.failedCount == 1 }
        snapshot = FileTranscriptionSettingsSnapshot(
            provider: .local,
            languageHints: ["de"],
            localModelName: "changed-model"
        )

        service.retryFailed()
        try await waitUntil { !service.isProcessing && service.completedCount == 1 }

        XCTAssertEqual(transcriber.receivedSettings.map(\.provider), [.cloud, .cloud])
        XCTAssertEqual(transcriber.receivedSettings.map(\.languageHints), [[], []])
        XCTAssertEqual(completionSoundCount, 1)
    }

    func test_activeItemExposesExactServerProgressWithoutInventingAggregateProgress() async throws {
        let transcriber = BatchTestTranscriber(
            delay: .milliseconds(500),
            progressUpdates: [JobProgressUpdate(status: .processing, progressPercent: 40)]
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )
        let firstURL = URL(fileURLWithPath: "/tmp/first.mov")

        service.beginBatch(urls: [firstURL, URL(fileURLWithPath: "/tmp/second.mov")])
        try await waitUntil {
            service.items.first?.progressFraction == 0.4
                && service.items.first.map { service.isActive($0.id) } == true
        }

        XCTAssertEqual(service.progress, 0, accuracy: 0.001)
        XCTAssertNotNil(service.items.first?.startedAt)
        XCTAssertNil(service.items.first?.finishedAt)

        service.cancelAll()
        try await waitUntil { !service.isProcessing }
    }

    func test_statusWithoutProgressClearsPreviousServerPercentage() async throws {
        let transcriber = BatchTestTranscriber(
            delay: .milliseconds(500),
            progressUpdates: [
                JobProgressUpdate(status: .processing, progressPercent: 40),
                JobProgressUpdate(status: .finalizing)
            ]
        )
        let service = FileTranscriptionBatchService(
            preparer: BatchTestPreparer(),
            transcriber: transcriber,
            recordingStore: BatchTestRecordingStore(),
            settingsSnapshot: { .testValue },
            playCompletionSound: {}
        )

        service.beginBatch(urls: [URL(fileURLWithPath: "/tmp/progress.mov")])
        try await waitUntil { service.items.first?.status == .finalizing }

        XCTAssertNil(service.items.first?.progressFraction)

        service.cancelAll()
        try await waitUntil { !service.isProcessing }
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for batch state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class BatchTestPreparer: FileTranscriptionBatchPreparing {
    private let failingSourceNames: Set<String>
    private let outputDirectory: URL
    private(set) var preparedSourceNames: [String] = []

    init(
        failingSourceNames: Set<String> = [],
        outputDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DidunyBatchTests-\(UUID().uuidString)")
    ) {
        self.failingSourceNames = failingSourceNames
        self.outputDirectory = outputDirectory
    }

    func prepare(sourceURL: URL) async throws -> ImportedMediaAudioPreparer.PreparedAudio {
        preparedSourceNames.append(sourceURL.lastPathComponent)
        if failingSourceNames.contains(sourceURL.lastPathComponent) {
            throw BatchTestError.preparationFailed
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("m4a")
        try Data("test audio".utf8).write(to: outputURL)
        return ImportedMediaAudioPreparer.PreparedAudio(
            fileURL: outputURL,
            durationSeconds: 12
        )
    }
}

private final class BatchTestTranscriber: FileTranscriptionBatchTranscribing {
    private(set) var transcribedFileNames: [String] = []
    private(set) var receivedSettings: [FileTranscriptionSettingsSnapshot] = []
    private(set) var maximumConcurrentCount = 0
    private var concurrentCount = 0
    private var remainingFailures: Int
    private let delay: Duration
    private let preflightErrorMessage: String?
    private let progressUpdates: [JobProgressUpdate]

    init(
        delay: Duration = .milliseconds(20),
        preflightError: String? = nil,
        failureCount: Int = 0,
        progressUpdates: [JobProgressUpdate] = []
    ) {
        self.delay = delay
        preflightErrorMessage = preflightError
        remainingFailures = failureCount
        self.progressUpdates = progressUpdates
    }

    func preflightError(for _: FileTranscriptionSettingsSnapshot) -> String? {
        preflightErrorMessage
    }

    func transcribe(
        audioFileURL: URL,
        settings: FileTranscriptionSettingsSnapshot,
        onUpdate: @escaping (JobProgressUpdate) -> Void
    ) async throws -> String {
        transcribedFileNames.append(audioFileURL.lastPathComponent)
        receivedSettings.append(settings)
        concurrentCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, concurrentCount)
        defer { concurrentCount -= 1 }
        for update in progressUpdates {
            onUpdate(update)
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: delay)
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw BatchTestError.transcriptionFailed
        }
        return "Transcript for \(audioFileURL.lastPathComponent)"
    }
}

@MainActor
private final class BatchTestRecordingStore: FileTranscriptionBatchRecordingStoring {
    private let duplicate: BatchTranscriptionDuplicate?

    init(duplicate: BatchTranscriptionDuplicate? = nil) {
        self.duplicate = duplicate
    }

    func completedDuplicate(sourceFileName _: String) -> BatchTranscriptionDuplicate? {
        duplicate
    }

    func savePreparedAudio(
        at _: URL,
        durationSeconds _: TimeInterval,
        sourceFileName _: String
    ) -> UUID? {
        nil
    }

    func audioFileURL(recordingID _: UUID) -> URL? {
        nil
    }

    func markProcessing(recordingID _: UUID) {}
    func markCompleted(recordingID _: UUID, text _: String) {}
    func markFailed(recordingID _: UUID, error _: String) {}
    func markUnprocessed(recordingID _: UUID) {}
}

private enum BatchTestError: Error {
    case preparationFailed
    case transcriptionFailed
}

private extension FileTranscriptionSettingsSnapshot {
    static let testValue = FileTranscriptionSettingsSnapshot(
        provider: .cloud,
        languageHints: [],
        localModelName: ""
    )

    static let localTestValue = FileTranscriptionSettingsSnapshot(
        provider: .local,
        languageHints: [],
        localModelName: "test-model"
    )
}
