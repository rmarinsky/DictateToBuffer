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

    func test_start_processesFilesSequentiallyAndCompletesOnce() async throws {
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
            URL(fileURLWithPath: "/tmp/second.mp4")
        ])
        service.startIfNeeded()
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(service.items.map(\.status), [.completed, .completed])
        XCTAssertEqual(transcriber.maximumConcurrentCount, 1)
        XCTAssertEqual(transcriber.transcribedFileNames, ["first.m4a", "second.m4a"])
        XCTAssertEqual(completionSoundCount, 1)
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
        let transcriber = BatchTestTranscriber(delay: .milliseconds(80))
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
        try await waitUntil { !service.isProcessing && service.finishedCount == 2 }

        XCTAssertEqual(transcriber.transcribedFileNames, ["first.m4a", "second.m4a"])
        XCTAssertEqual(service.items.map(\.status), [.completed, .completed])
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
    private(set) var maximumConcurrentCount = 0
    private var concurrentCount = 0
    private let delay: Duration
    private let preflightErrorMessage: String?

    init(
        delay: Duration = .milliseconds(20),
        preflightError: String? = nil
    ) {
        self.delay = delay
        preflightErrorMessage = preflightError
    }

    func preflightError(for _: FileTranscriptionSettingsSnapshot) -> String? {
        preflightErrorMessage
    }

    func transcribe(
        audioFileURL: URL,
        settings _: FileTranscriptionSettingsSnapshot,
        onUpdate _: @escaping (JobStatus) -> Void
    ) async throws -> String {
        transcribedFileNames.append(audioFileURL.lastPathComponent)
        concurrentCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, concurrentCount)
        defer { concurrentCount -= 1 }
        try await Task.sleep(for: delay)
        return "Transcript for \(audioFileURL.lastPathComponent)"
    }
}

@MainActor
private final class BatchTestRecordingStore: FileTranscriptionBatchRecordingStoring {
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
}

private extension FileTranscriptionSettingsSnapshot {
    static let testValue = FileTranscriptionSettingsSnapshot(
        provider: .cloud,
        languageHints: [],
        localModelName: ""
    )
}
