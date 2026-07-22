import AppKit
import Foundation
import Observation

struct FileTranscriptionSettingsSnapshot {
    let provider: TranscriptionProvider
    let languageHints: [String]
    let localModelName: String

    @MainActor
    static func current() -> Self {
        let settings = SettingsStorage.shared
        return Self(
            provider: settings.effectiveTranscriptionProvider,
            languageHints: settings.speechLanguageHints,
            localModelName: settings.selectedWhisperModel
        )
    }
}

struct BatchTranscriptionItem: Identifiable, Equatable {
    enum Status: Equatable {
        case queued
        case preparing
        case uploading
        case processing
        case finalizing
        case completed
        case failed
        case cancelled

        var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled:
                true
            default:
                false
            }
        }
    }

    let id: UUID
    let sourceURL: URL
    var durationSeconds: TimeInterval?
    var status: Status
    var transcriptionText: String?
    var recordingID: UUID?
    var errorMessage: String?
    var progressFraction: Double?
    var startedAt: Date?
    var finishedAt: Date?

    init(id: UUID = UUID(), sourceURL: URL) {
        self.id = id
        self.sourceURL = sourceURL
        status = .queued
    }

    func elapsedTime(at date: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, (finishedAt ?? date).timeIntervalSince(startedAt))
    }
}

protocol FileTranscriptionBatchPreparing: AnyObject {
    func prepare(sourceURL: URL) async throws -> ImportedMediaAudioPreparer.PreparedAudio
}

extension ImportedMediaAudioPreparer: FileTranscriptionBatchPreparing {}

protocol FileTranscriptionBatchTranscribing: AnyObject {
    func preflightError(for settings: FileTranscriptionSettingsSnapshot) -> String?
    func transcribe(
        audioFileURL: URL,
        settings: FileTranscriptionSettingsSnapshot,
        onUpdate: @escaping (JobProgressUpdate) -> Void
    ) async throws -> String
}

@MainActor
protocol FileTranscriptionBatchRecordingStoring: AnyObject {
    func savePreparedAudio(
        at audioURL: URL,
        durationSeconds: TimeInterval,
        sourceFileName: String
    ) -> UUID?
    func audioFileURL(recordingID: UUID) -> URL?
    func markProcessing(recordingID: UUID)
    func markCompleted(recordingID: UUID, text: String)
    func markFailed(recordingID: UUID, error: String)
    func markUnprocessed(recordingID: UUID)
}

@Observable
@MainActor
final class FileTranscriptionBatchService {
    static let shared = FileTranscriptionBatchService(
        preparer: ImportedMediaAudioPreparer(),
        transcriber: LiveFileTranscriptionBatchTranscriber(),
        recordingStore: LiveFileTranscriptionBatchRecordingStore(),
        settingsSnapshot: { .current() },
        playCompletionSound: {
            guard SettingsStorage.shared.playSoundOnCompletion else { return }
            NSSound(named: .init("Funk"))?.play()
        }
    )

    private(set) var items: [BatchTranscriptionItem] = []
    private(set) var isProcessing = false
    private(set) var currentItemID: UUID?
    private(set) var batchError: String?

    var finishedCount: Int {
        items.count(where: { $0.status.isTerminal })
    }

    var completedCount: Int {
        items.count(where: { $0.status == .completed })
    }

    var failedCount: Int {
        items.count(where: { $0.status == .failed })
    }

    var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(finishedCount) / Double(items.count)
    }

    var currentItem: BatchTranscriptionItem? {
        guard let currentItemID else { return nil }
        return items.first(where: { $0.id == currentItemID })
    }

    private let preparer: FileTranscriptionBatchPreparing
    private let transcriber: FileTranscriptionBatchTranscribing
    private let recordingStore: FileTranscriptionBatchRecordingStoring
    private let settingsSnapshot: @MainActor () -> FileTranscriptionSettingsSnapshot
    private let playCompletionSound: @MainActor () -> Void

    private var processingTask: Task<Void, Never>?
    private var activeSettingsSnapshot: FileTranscriptionSettingsSnapshot?
    private var hasPlayedCompletionSound = false

    init(
        preparer: FileTranscriptionBatchPreparing,
        transcriber: FileTranscriptionBatchTranscribing,
        recordingStore: FileTranscriptionBatchRecordingStoring,
        settingsSnapshot: @escaping @MainActor () -> FileTranscriptionSettingsSnapshot,
        playCompletionSound: @escaping @MainActor () -> Void
    ) {
        self.preparer = preparer
        self.transcriber = transcriber
        self.recordingStore = recordingStore
        self.settingsSnapshot = settingsSnapshot
        self.playCompletionSound = playCompletionSound
    }

    func beginBatch(urls: [URL]) {
        if !isProcessing, items.allSatisfy(\.status.isTerminal) {
            items.removeAll()
            activeSettingsSnapshot = nil
            hasPlayedCompletionSound = false
        }
        add(urls: urls)
        startIfNeeded()
    }

    func add(urls: [URL]) {
        let existingURLs = Set(items.map(\.sourceURL.standardizedFileURL))
        var addedURLs = Set<URL>()

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard !existingURLs.contains(standardizedURL),
                  addedURLs.insert(standardizedURL).inserted
            else { continue }

            items.append(BatchTranscriptionItem(sourceURL: standardizedURL))
        }
    }

    func startIfNeeded() {
        guard processingTask == nil,
              items.contains(where: { $0.status == .queued })
        else { return }

        let snapshot = activeSettingsSnapshot ?? settingsSnapshot()
        if let error = transcriber.preflightError(for: snapshot) {
            batchError = error
            return
        }

        activeSettingsSnapshot = snapshot
        batchError = nil
        isProcessing = true
        processingTask = Task { [weak self] in
            await self?.processQueuedItems(settings: snapshot)
        }
    }

    func retry(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for index in items.indices where ids.contains(items[index].id) {
            guard items[index].status == .failed || items[index].status == .cancelled else { continue }
            items[index].status = .queued
            items[index].errorMessage = nil
            items[index].transcriptionText = nil
            items[index].progressFraction = nil
            items[index].startedAt = nil
            items[index].finishedAt = nil
        }
        startIfNeeded()
    }

    func retryFailed() {
        retry(ids: Set(items.filter { $0.status == .failed }.map(\.id)))
    }

    func cancelAll() {
        for index in items.indices where items[index].status == .queued {
            items[index].status = .cancelled
        }
        processingTask?.cancel()
    }

    func clearFinished() {
        guard !isProcessing else { return }
        items.removeAll(where: { $0.status.isTerminal })
        batchError = nil
        if items.isEmpty {
            activeSettingsSnapshot = nil
            hasPlayedCompletionSound = false
        }
    }

    private func processQueuedItems(settings: FileTranscriptionSettingsSnapshot) async {
        let activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Transcribing imported media batch"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activityToken)
            processingTask = nil
            currentItemID = nil
            isProcessing = false
            let finishedBatch = !items.isEmpty && items.allSatisfy(\.status.isTerminal)
            if !Task.isCancelled, finishedBatch, !hasPlayedCompletionSound {
                hasPlayedCompletionSound = true
                playCompletionSound()
            }
        }

        while !Task.isCancelled {
            guard let itemID = items.first(where: { $0.status == .queued })?.id else { break }
            currentItemID = itemID
            await process(itemID: itemID, settings: settings)
        }
    }

    private func process(
        itemID: UUID,
        settings: FileTranscriptionSettingsSnapshot
    ) async {
        guard let initialIndex = index(of: itemID) else { return }

        var recordingID = items[initialIndex].recordingID
        var audioURL: URL?
        var temporaryAudio: ImportedMediaAudioPreparer.PreparedAudio?

        do {
            try Task.checkCancellation()
            markStarted(itemID)

            let storedAudioURL = recordingID.flatMap {
                recordingStore.audioFileURL(recordingID: $0)
            }
            if let recordingID, let storedAudioURL {
                audioURL = storedAudioURL
                recordingStore.markProcessing(recordingID: recordingID)
            } else {
                update(itemID) {
                    $0.status = .preparing
                }

                let preparedAudio = try await preparer.prepare(
                    sourceURL: items[initialIndex].sourceURL
                )
                temporaryAudio = preparedAudio
                try Task.checkCancellation()

                audioURL = preparedAudio.fileURL
                update(itemID) { $0.durationSeconds = preparedAudio.durationSeconds }

                recordingID = recordingStore.savePreparedAudio(
                    at: preparedAudio.fileURL,
                    durationSeconds: preparedAudio.durationSeconds,
                    sourceFileName: items[initialIndex].sourceURL.lastPathComponent
                )
                if let recordingID {
                    update(itemID) { $0.recordingID = recordingID }
                    recordingStore.markProcessing(recordingID: recordingID)
                }
            }

            guard let audioURL else {
                throw CocoaError(.fileNoSuchFile)
            }

            update(itemID) { $0.status = settings.provider == .cloud ? .uploading : .processing }
            let text = try await transcriber.transcribe(
                audioFileURL: audioURL,
                settings: settings
            ) { [weak self] progressUpdate in
                Task { @MainActor in
                    self?.apply(progressUpdate: progressUpdate, to: itemID)
                }
            }
            try Task.checkCancellation()

            if let recordingID {
                recordingStore.markCompleted(recordingID: recordingID, text: text)
            }
            update(itemID) {
                $0.status = .completed
                $0.progressFraction = 1
                $0.finishedAt = Date()
                $0.transcriptionText = text
                $0.errorMessage = nil
            }
        } catch is CancellationError {
            if let recordingID {
                recordingStore.markUnprocessed(recordingID: recordingID)
            }
            update(itemID) {
                $0.status = .cancelled
                $0.finishedAt = Date()
                $0.errorMessage = nil
            }
        } catch {
            let message = error.localizedDescription
            if let recordingID {
                recordingStore.markFailed(recordingID: recordingID, error: message)
            }
            update(itemID) {
                $0.status = .failed
                $0.finishedAt = Date()
                $0.errorMessage = message
            }
        }

        temporaryAudio?.removeTemporaryFile()
    }

    private func markStarted(_ itemID: UUID) {
        update(itemID) {
            $0.startedAt = Date()
            $0.finishedAt = nil
            $0.progressFraction = nil
            $0.errorMessage = nil
        }
    }

    private func apply(progressUpdate: JobProgressUpdate, to itemID: UUID) {
        update(itemID) { item in
            guard !item.status.isTerminal else { return }
            switch progressUpdate.status {
            case .queued:
                item.status = .queued
            case .uploading:
                item.status = .uploading
            case .processing:
                item.status = .processing
            case .finalizing:
                item.status = .finalizing
            case .completed:
                break
            case .error:
                item.status = .failed
            }
            item.progressFraction = progressUpdate.fractionCompleted
        }
    }

    private func index(of itemID: UUID) -> Int? {
        items.firstIndex(where: { $0.id == itemID })
    }

    private func update(
        _ itemID: UUID,
        _ mutation: (inout BatchTranscriptionItem) -> Void
    ) {
        guard let index = index(of: itemID) else { return }
        mutation(&items[index])
    }
}

private final class LiveFileTranscriptionBatchTranscriber: FileTranscriptionBatchTranscribing {
    func preflightError(for settings: FileTranscriptionSettingsSnapshot) -> String? {
        switch settings.provider {
        case .cloud:
            return AuthService.hasStoredSession ? nil : "Log in to use Cloud transcription."
        case .local:
            guard let model = WhisperModelManager.availableModels.first(where: {
                $0.name == settings.localModelName
            }), WhisperModelManager.shared.isModelDownloaded(model)
            else {
                return "No local Whisper model downloaded. Log in for Cloud or download a model in Settings."
            }
            return nil
        }
    }

    func transcribe(
        audioFileURL: URL,
        settings: FileTranscriptionSettingsSnapshot,
        onUpdate: @escaping (JobProgressUpdate) -> Void
    ) async throws -> String {
        switch settings.provider {
        case .cloud:
            var config: [String: Any] = ["mode": "transcribe"]
            if !settings.languageHints.isEmpty {
                config["language_hints"] = settings.languageHints
                config["language_hints_strict"] = true
            }
            return try await AsyncTranscriptionJobService().transcribeFileWithRetry(
                audioFileURL: audioFileURL,
                config: config,
                onProgressUpdate: onUpdate
            )
        case .local:
            onUpdate(JobProgressUpdate(status: .processing))
            let audioData = try await Task.detached(priority: .utility) {
                try Data(contentsOf: audioFileURL, options: .mappedIfSafe)
            }.value
            let service = WhisperTranscriptionService()
            service.modelNameOverride = settings.localModelName
            return try await service.transcribe(audioData: audioData)
        }
    }
}

@MainActor
private final class LiveFileTranscriptionBatchRecordingStore: FileTranscriptionBatchRecordingStoring {
    private let storage = RecordingsLibraryStorage.shared

    func savePreparedAudio(
        at audioURL: URL,
        durationSeconds: TimeInterval,
        sourceFileName: String
    ) -> UUID? {
        storage.saveRecording(
            audioURL: audioURL,
            type: .fileTranscription,
            duration: durationSeconds,
            sourceFileName: sourceFileName
        )
    }

    func audioFileURL(recordingID: UUID) -> URL? {
        guard let recording = storage.recordings.first(where: { $0.id == recordingID }) else {
            return nil
        }
        let url = storage.audioFileURL(for: recording)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func markProcessing(recordingID: UUID) {
        storage.updateRecording(id: recordingID, status: .processing, error: nil)
    }

    func markCompleted(recordingID: UUID, text: String) {
        storage.updateRecording(id: recordingID, status: .transcribed, text: text, error: nil)
    }

    func markFailed(recordingID: UUID, error: String) {
        storage.updateRecording(id: recordingID, status: .failed, error: error)
    }

    func markUnprocessed(recordingID: UUID) {
        storage.updateRecording(id: recordingID, status: .unprocessed, error: nil)
    }
}
