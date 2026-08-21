import Foundation

struct RecordingDeletionStagedFile: Codable, Equatable {
    let originalPath: String
    let stagedPath: String
}

struct RecordingDeletionRecovery: Codable, Equatable {
    let recordings: [Recording]
    let stagedFiles: [RecordingDeletionStagedFile]
}

@Observable
@MainActor
final class RecordingsLibraryStorage {
    static let shared = RecordingsLibraryStorage()

    private(set) var recordings: [Recording] = []

    private let fileManager = FileManager.default
    private let appSupportDir: URL
    private let recordingsDir: URL
    private let metadataURL: URL
    private let deletionRecoveryURL: URL
    private let batchStorage: TranscriptionBatchStorage
    private let metadataWriteQueue = DispatchQueue(label: "ua.com.rmarinsky.diduny.recordings-metadata")

    init(
        baseDirectory: URL? = nil,
        batchStorage: TranscriptionBatchStorage? = nil
    ) {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "Diduny"
        let appDir = baseDirectory ?? appSupport.appendingPathComponent(bundleID)
        appSupportDir = appDir
        self.batchStorage = batchStorage ?? .shared

        let recDir = appDir.appendingPathComponent("Recordings")
        try? fm.createDirectory(at: recDir, withIntermediateDirectories: true)
        recordingsDir = recDir

        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        metadataURL = appDir.appendingPathComponent("recordings_metadata.json")
        deletionRecoveryURL = appDir.appendingPathComponent("recordings_delete_recovery.json")

        loadAndPrune()
    }

    // MARK: - Save (from Data — voice/translation)

    @discardableResult
    func saveRecording(
        id: UUID? = nil,
        audioData: Data,
        type: Recording.RecordingType,
        duration: TimeInterval,
        transcriptionText: String? = nil,
        sourceDevice: RecordingDeviceInfo? = nil,
        translationTargetLanguageCode: String? = nil,
        sourceFileName: String? = nil,
        sourceFileSizeBytes: Int64? = nil,
        remoteSource: RemoteMediaSourceMetadata? = nil,
        sourceCaptionArtifacts: [TranscriptArtifact]? = nil,
        generatedTranscriptProvenance: GeneratedTranscriptProvenance? = nil,
        transcriptSegments: [TimedTranscriptSegment]? = nil,
        createdAt: Date = Date(),
        recoverySource: RecoverySource? = nil,
        forceSave: Bool = false
    ) -> UUID? {
        guard forceSave || shouldSaveRecording(type: type) else { return nil }

        let recordingID = id ?? UUID()
        let fileExtension = detectedAudioFileExtension(for: audioData)
        let fileName = "\(recordingID.uuidString).\(fileExtension)"
        let fileURL = recordingsDir.appendingPathComponent(fileName)

        do {
            try audioData.write(to: fileURL)
        } catch {
            Log.app.error("Failed to save recording audio: \(error.localizedDescription)")
            return nil
        }

        let status: Recording.ProcessingStatus = if transcriptionText != nil {
            type.usesTranslatedStatusWhenSavedWithText ? .translated : .transcribed
        } else {
            .unprocessed
        }
        let recording = Recording(
            id: recordingID,
            createdAt: createdAt,
            endedAt: createdAt.addingTimeInterval(duration),
            type: type,
            audioFileName: fileName,
            durationSeconds: duration,
            fileSizeBytes: Int64(audioData.count),
            status: status,
            transcriptionText: transcriptionText,
            processedAt: transcriptionText != nil ? Date() : nil,
            sourceDevice: sourceDevice,
            translationTargetLanguageCode: translationTargetLanguageCode,
            recoverySource: recoverySource,
            sourceFileName: sourceFileName,
            sourceFileSizeBytes: sourceFileSizeBytes,
            remoteSource: remoteSource,
            sourceCaptionArtifacts: sourceCaptionArtifacts,
            generatedTranscriptProvenance: generatedTranscriptProvenance,
            transcriptSegments: transcriptSegments
        )

        recordings.insert(recording, at: 0)
        if forceSave {
            guard saveMetadataSynchronously() else {
                recordings.removeAll { $0.id == recordingID }
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        } else {
            saveMetadata()
        }
        if !forceSave {
            pruneExpiredRecordingsIfEnabled()
        }
        Log.app.info("Recording saved: \(type.rawValue), \(audioData.count) bytes")
        return recordingID
    }

    // MARK: - Save (from URL — meetings, copies file)

    @discardableResult
    func saveRecording(
        id: UUID? = nil,
        audioURL: URL,
        type: Recording.RecordingType,
        duration: TimeInterval,
        transcriptionText: String? = nil,
        sourceDevice: RecordingDeviceInfo? = nil,
        translationTargetLanguageCode: String? = nil,
        sourceFileName: String? = nil,
        sourceFileSizeBytes: Int64? = nil,
        remoteSource: RemoteMediaSourceMetadata? = nil,
        sourceCaptionArtifacts: [TranscriptArtifact]? = nil,
        generatedTranscriptProvenance: GeneratedTranscriptProvenance? = nil,
        transcriptSegments: [TimedTranscriptSegment]? = nil,
        createdAt: Date = Date(),
        recoverySource: RecoverySource? = nil,
        forceSave: Bool = false
    ) -> UUID? {
        guard forceSave || shouldSaveRecording(type: type) else { return nil }

        let recordingID = id ?? UUID()
        let ext = audioURL.pathExtension.isEmpty ? "wav" : audioURL.pathExtension
        let fileName = "\(recordingID.uuidString).\(ext)"
        let destURL = recordingsDir.appendingPathComponent(fileName)

        do {
            try fileManager.copyItem(at: audioURL, to: destURL)
        } catch {
            Log.app.error("Failed to copy recording file: \(error.localizedDescription)")
            return nil
        }

        let fileSize: Int64 = if let attrs = try? fileManager.attributesOfItem(atPath: destURL.path),
                                 let size = attrs[.size] as? Int64
        {
            size
        } else {
            0
        }

        let status: Recording.ProcessingStatus = if transcriptionText != nil {
            type.usesTranslatedStatusWhenSavedWithText ? .translated : .transcribed
        } else {
            .unprocessed
        }

        let recording = Recording(
            id: recordingID,
            createdAt: createdAt,
            endedAt: createdAt.addingTimeInterval(duration),
            type: type,
            audioFileName: fileName,
            durationSeconds: duration,
            fileSizeBytes: fileSize,
            status: status,
            transcriptionText: transcriptionText,
            processedAt: transcriptionText != nil ? Date() : nil,
            sourceDevice: sourceDevice,
            translationTargetLanguageCode: translationTargetLanguageCode,
            recoverySource: recoverySource,
            sourceFileName: sourceFileName,
            sourceFileSizeBytes: sourceFileSizeBytes,
            remoteSource: remoteSource,
            sourceCaptionArtifacts: sourceCaptionArtifacts,
            generatedTranscriptProvenance: generatedTranscriptProvenance,
            transcriptSegments: transcriptSegments
        )

        recordings.insert(recording, at: 0)
        if forceSave {
            guard saveMetadataSynchronously() else {
                recordings.removeAll { $0.id == recordingID }
                try? fileManager.removeItem(at: destURL)
                return nil
            }
        } else {
            saveMetadata()
        }
        if !forceSave {
            pruneExpiredRecordingsIfEnabled()
        }
        Log.app.info("Recording saved from file: \(type.rawValue), \(fileSize) bytes")
        return recordingID
    }

    // MARK: - Live meeting session (row from start)

    /// Creates a library row at meeting start. `id` must match the in-progress store UUID.
    /// Always force-saves so retention "Never" cannot skip recovery visibility.
    @discardableResult
    func beginMeetingRecording(
        id: UUID,
        type: Recording.RecordingType,
        createdAt: Date = Date(),
        sourceDevice: RecordingDeviceInfo? = nil,
        translationTargetLanguageCode: String? = nil
    ) -> UUID? {
        guard type.isMeetingLike else {
            Log.app.error("beginMeetingRecording called with non-meeting type: \(type.rawValue)")
            return nil
        }

        if let index = recordings.firstIndex(where: { $0.id == id }) {
            recordings[index].status = .recording
            recordings[index].endedAt = nil
            recordings[index].statusDetail = nil
            recordings[index].errorMessage = nil
            guard saveMetadataSynchronously() else { return nil }
            return id
        }

        let recording = Recording(
            id: id,
            createdAt: createdAt,
            endedAt: nil,
            type: type,
            audioFileName: "",
            durationSeconds: 0,
            fileSizeBytes: 0,
            status: .recording,
            sourceDevice: sourceDevice,
            translationTargetLanguageCode: translationTargetLanguageCode
        )
        recordings.insert(recording, at: 0)
        guard saveMetadataSynchronously() else {
            recordings.removeAll { $0.id == id }
            return nil
        }
        Log.app.info("Meeting library row begun: \(id.uuidString)")
        return id
    }

    /// Attaches durable audio to an existing live/recovery row and advances status.
    @discardableResult
    func finalizeInProgressRecording(
        id: UUID,
        audioURL: URL,
        duration: TimeInterval,
        endedAt: Date,
        status: Recording.ProcessingStatus,
        recoverySource: RecoverySource? = nil,
        forceSave: Bool = true
    ) -> Bool {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return false }

        let ext = audioURL.pathExtension.isEmpty ? "wav" : audioURL.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        let destURL = recordingsDir.appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: audioURL, to: destURL)
        } catch {
            Log.app.error("Failed to finalize recording audio: \(error.localizedDescription)")
            return false
        }

        let fileSize: Int64 = if let attrs = try? fileManager.attributesOfItem(atPath: destURL.path),
                                 let size = attrs[.size] as? Int64
        {
            size
        } else {
            0
        }

        let previous = recordings[index]
        recordings[index] = Recording(
            id: previous.id,
            createdAt: previous.createdAt,
            endedAt: endedAt,
            type: previous.type,
            audioFileName: fileName,
            durationSeconds: duration,
            fileSizeBytes: fileSize,
            status: status,
            transcriptionText: previous.transcriptionText,
            errorMessage: nil,
            statusDetail: nil,
            processedAt: previous.processedAt,
            chapters: previous.chapters,
            sourceDevice: previous.sourceDevice,
            translationTargetLanguageCode: previous.translationTargetLanguageCode,
            recoverySource: recoverySource ?? previous.recoverySource,
            sourceFileName: previous.sourceFileName,
            sourceFileSizeBytes: previous.sourceFileSizeBytes,
            remoteSource: previous.remoteSource,
            sourceCaptionArtifacts: previous.sourceCaptionArtifacts,
            generatedTranscriptProvenance: previous.generatedTranscriptProvenance,
            transcriptSegments: previous.transcriptSegments,
            title: previous.title,
            description: previous.description,
            transcriptHistory: previous.transcriptHistory
        )

        if forceSave {
            guard saveMetadataSynchronously() else {
                recordings[index] = previous
                try? fileManager.removeItem(at: destURL)
                return false
            }
        } else {
            saveMetadata()
        }
        Log.app.info("Meeting library row finalized: \(id.uuidString), status=\(status.rawValue)")
        return true
    }

    @discardableResult
    func markNeedsRecovery(
        id: UUID,
        endedAt: Date = Date(),
        durationSeconds: TimeInterval? = nil,
        recoverySource: RecoverySource = .orphanedSession
    ) -> Bool {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return false }
        let previous = recordings[index]
        recordings[index].status = .needsRecovery
        recordings[index].endedAt = endedAt
        recordings[index].recoverySource = previous.recoverySource ?? recoverySource
        recordings[index].statusDetail = nil
        if let durationSeconds {
            // durationSeconds is `let` — rebuild via finalize-style memberwise if needed.
            // Use a full reconstruct to update duration.
            recordings[index] = Recording(
                id: previous.id,
                createdAt: previous.createdAt,
                endedAt: endedAt,
                type: previous.type,
                audioFileName: previous.audioFileName,
                durationSeconds: durationSeconds,
                fileSizeBytes: previous.fileSizeBytes,
                status: .needsRecovery,
                transcriptionText: previous.transcriptionText,
                errorMessage: previous.errorMessage,
                statusDetail: nil,
                processedAt: previous.processedAt,
                chapters: previous.chapters,
                sourceDevice: previous.sourceDevice,
                translationTargetLanguageCode: previous.translationTargetLanguageCode,
                recoverySource: previous.recoverySource ?? recoverySource,
                sourceFileName: previous.sourceFileName,
                sourceFileSizeBytes: previous.sourceFileSizeBytes,
                remoteSource: previous.remoteSource,
                sourceCaptionArtifacts: previous.sourceCaptionArtifacts,
                generatedTranscriptProvenance: previous.generatedTranscriptProvenance,
                transcriptSegments: previous.transcriptSegments,
                title: previous.title,
                description: previous.description,
                transcriptHistory: previous.transcriptHistory
            )
        }
        guard saveMetadataSynchronously() else {
            recordings[index] = previous
            return false
        }
        return true
    }

    func updateStatusDetail(id: UUID, detail: String?) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].statusDetail = detail
        saveMetadata()
    }

    func hasPlayableAudio(for recording: Recording) -> Bool {
        guard recording.hasAttachedAudio else { return false }
        return fileManager.fileExists(atPath: audioFileURL(for: recording).path)
    }

    // MARK: - Delete

    @discardableResult
    func deleteRecording(_ recording: Recording) -> Bool {
        deleteStoredRecordings(Set([recording.id])) {
            try batchStorage.removeRecordingReferences(Set([recording.id]))
        }
    }

    @discardableResult
    func deleteRecordings(_ ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return true }
        return deleteStoredRecordings(ids) {
            try batchStorage.removeRecordingReferences(ids)
        }
    }

    @discardableResult
    func deleteBatch(_ batch: TranscriptionBatch) -> Bool {
        deleteStoredRecordings(Set(batch.recordingIDs)) {
            _ = try batchStorage.delete(batchID: batch.id)
        }
    }

    private func deleteStoredRecordings(
        _ ids: Set<UUID>,
        updateBatchMetadata: () throws -> Void
    ) -> Bool {
        let previousRecordings = recordings
        let targets = recordings.filter { ids.contains($0.id) }
        let stagedFiles = targets.compactMap { recording -> RecordingDeletionStagedFile? in
            let original = recordingsDir.appendingPathComponent(recording.audioFileName)
            guard fileManager.fileExists(atPath: original.path) else { return nil }
            return RecordingDeletionStagedFile(
                originalPath: original.path,
                stagedPath: recordingsDir.appendingPathComponent(
                    ".\(recording.audioFileName).deleting-\(UUID().uuidString)"
                ).path
            )
        }
        let recovery = RecordingDeletionRecovery(
            recordings: previousRecordings,
            stagedFiles: stagedFiles
        )

        guard Self.writeDeletionRecovery(recovery, to: deletionRecoveryURL) else {
            return false
        }

        func restoreStagedFiles() {
            for file in stagedFiles.reversed() where fileManager.fileExists(atPath: file.stagedPath) {
                do {
                    try fileManager.moveItem(
                        at: URL(fileURLWithPath: file.stagedPath),
                        to: URL(fileURLWithPath: file.originalPath)
                    )
                } catch {
                    Log.app.error("Failed to restore staged recording file: \(error.localizedDescription)")
                }
            }
        }

        do {
            for file in stagedFiles {
                try fileManager.moveItem(
                    at: URL(fileURLWithPath: file.originalPath),
                    to: URL(fileURLWithPath: file.stagedPath)
                )
            }
        } catch {
            restoreStagedFiles()
            try? fileManager.removeItem(at: deletionRecoveryURL)
            Log.app.error("Failed to stage recording deletion: \(error.localizedDescription)")
            return false
        }

        recordings.removeAll { ids.contains($0.id) }
        guard saveMetadataSynchronously() else {
            recordings = previousRecordings
            restoreStagedFiles()
            return false
        }

        do {
            try updateBatchMetadata()
        } catch {
            recordings = previousRecordings
            if saveMetadataSynchronously() {
                try? fileManager.removeItem(at: deletionRecoveryURL)
            } else {
                Log.app.error("Failed to restore recordings metadata after batch update failure")
            }
            restoreStagedFiles()
            Log.app.error("Failed to update transcription batches during deletion: \(error.localizedDescription)")
            return false
        }

        for file in stagedFiles {
            do {
                try fileManager.removeItem(at: URL(fileURLWithPath: file.stagedPath))
            } catch {
                Log.app.warning("Failed to clean staged recording file: \(error.localizedDescription)")
            }
        }
        try? fileManager.removeItem(at: deletionRecoveryURL)
        return true
    }

    func pruneExpiredRecordings(now: Date = Date()) {
        let expiredIds = Set(recordings.compactMap { recording -> UUID? in
            // Never auto-prune live or recovery rows.
            if recording.status.isInProgressCapture { return nil }
            let policy = SettingsStorage.shared.historyRetentionPolicy(for: recording.type)
            guard let cutoff = policy.expirationCutoff(now: now),
                  recording.createdAt <= cutoff
            else {
                return nil
            }
            return recording.id
        })

        guard !expiredIds.isEmpty else { return }
        deleteRecordings(expiredIds)
        Log.app.info("Pruned \(expiredIds.count) expired recording entries")
    }

    // MARK: - Update

    @discardableResult
    func updateDetails(id: UUID, title: String, description: String) -> Bool {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return false }
        let previous = recordings[index]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        recordings[index].title = trimmedTitle.isEmpty ? nil : trimmedTitle
        recordings[index].description = trimmedDescription.isEmpty ? nil : trimmedDescription
        guard saveMetadataSynchronously() else {
            recordings[index] = previous
            return false
        }
        return true
    }

    func updateRecording(
        id: UUID,
        status: Recording.ProcessingStatus,
        text: String? = nil,
        error: String? = nil,
        translationTargetLanguageCode: String? = nil
    ) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].status = status
        recordings[index].transcriptionText = text ?? recordings[index].transcriptionText
        recordings[index].errorMessage = error
        if let translationTargetLanguageCode {
            recordings[index].translationTargetLanguageCode = translationTargetLanguageCode
        }
        if status == .transcribed || status == .translated {
            recordings[index].processedAt = Date()
        }
        saveMetadata()
    }

    func updateRemoteArtifacts(
        id: UUID,
        remoteSource: RemoteMediaSourceMetadata? = nil,
        sourceCaptionArtifacts: [TranscriptArtifact]? = nil,
        generatedTranscriptProvenance: GeneratedTranscriptProvenance? = nil
    ) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        if let remoteSource {
            recordings[index].remoteSource = remoteSource
        }
        if let sourceCaptionArtifacts {
            recordings[index].sourceCaptionArtifacts = sourceCaptionArtifacts
        }
        if let generatedTranscriptProvenance {
            recordings[index].generatedTranscriptProvenance = generatedTranscriptProvenance
        }
        saveMetadata()
    }

    func completeTranscription(
        id: UUID,
        status: Recording.ProcessingStatus,
        text: String,
        segments: [TimedTranscriptSegment]?,
        translationTargetLanguageCode: String? = nil,
        generatedTranscriptProvenance: GeneratedTranscriptProvenance? = nil,
        kind: TranscriptVersion.Kind,
        provider: String? = nil,
        modelIdentifier: String? = nil,
        sourceLanguageCode: String? = nil
    ) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        let previous = recordings[index]
        let completedAt = Date()
        let version = TranscriptVersion(
            createdAt: completedAt,
            kind: kind,
            provider: provider,
            modelIdentifier: modelIdentifier,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: translationTargetLanguageCode,
            text: text,
            segments: segments,
            provenance: generatedTranscriptProvenance
        )
        recordings[index].transcriptHistory = recordings[index].resolvedTranscriptHistory + [version]
        recordings[index].status = status
        recordings[index].transcriptionText = text
        recordings[index].errorMessage = nil
        recordings[index].processedAt = completedAt
        recordings[index].transcriptSegments = segments
        recordings[index].translationTargetLanguageCode = translationTargetLanguageCode
        recordings[index].generatedTranscriptProvenance = generatedTranscriptProvenance
        if !saveMetadataSynchronously() {
            recordings[index] = previous
        }
    }

    func optimizeStoredRecordingIfNeeded(id: UUID) async -> URL? {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return nil }

        let recording = recordings[index]
        let sourceURL = audioFileURL(for: recording)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }

        let detectedExtension = detectedAudioFileExtension(for: sourceURL)

        if detectedExtension == "flac", sourceURL.pathExtension.lowercased() != "flac" {
            let normalizedURL = sourceURL.deletingPathExtension().appendingPathExtension("flac")
            return replaceStoredAudioFile(
                at: index,
                from: sourceURL,
                to: normalizedURL,
                moveOnly: true
            )
        }

        guard detectedExtension == "wav" else {
            return sourceURL
        }

        let compressedURL = await AudioCompressionService.compressToFLAC(wavURL: sourceURL)
        guard compressedURL != sourceURL else {
            return sourceURL
        }

        return replaceStoredAudioFile(
            at: index,
            from: sourceURL,
            to: compressedURL,
            moveOnly: false
        )
    }

    // MARK: - Audio File Access

    func audioFileURL(for recording: Recording) -> URL {
        recordingsDir.appendingPathComponent(recording.audioFileName)
    }

    // MARK: - Stats

    var totalSizeBytes: Int64 {
        recordings.reduce(0) { $0 + $1.fileSizeBytes }
    }

    // MARK: - Persistence

    private func loadAndPrune() {
        let url = metadataURL
        let recoveryURL = deletionRecoveryURL
        let recDir = recordingsDir
        let result: (recordings: [Recording], resetInterrupted: Bool)? = {
            let data: Data
            if let recoveryData = try? Data(contentsOf: recoveryURL),
               let recovery = try? Self.decodeDeletionRecovery(recoveryData)
            {
                for file in recovery.stagedFiles {
                    let original = URL(fileURLWithPath: file.originalPath)
                    let staged = URL(fileURLWithPath: file.stagedPath)
                    if FileManager.default.fileExists(atPath: staged.path),
                       !FileManager.default.fileExists(atPath: original.path)
                    {
                        try? FileManager.default.moveItem(at: staged, to: original)
                    }
                }
                guard recovery.stagedFiles.allSatisfy({
                    FileManager.default.fileExists(atPath: $0.originalPath)
                }) else {
                    Log.app.error("Recording deletion recovery still has missing media files")
                    return nil
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                guard let restoredData = try? encoder.encode(recovery.recordings) else { return nil }
                data = restoredData
                do {
                    try restoredData.write(to: url, options: .atomic)
                    try FileManager.default.removeItem(at: recoveryURL)
                } catch {
                    Log.app.error("Failed to restore recording deletion recovery: \(error.localizedDescription)")
                }
            } else {
                guard let metadata = try? Data(contentsOf: url) else { return nil }
                data = metadata
            }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var loaded = try decoder.decode([Recording].self, from: data)
                let resetInterrupted = Self.resetInterruptedProcessingStates(in: &loaded)
                // Prune orphans with a single directory scan instead of per-file fileExists
                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: recDir, includingPropertiesForKeys: nil
                ) {
                    let names = Set(contents.map(\.lastPathComponent))
                    loaded.removeAll { recording in
                        // Live / needs-recovery rows may have no durable audio yet.
                        if recording.audioFileName.isEmpty {
                            return !recording.status.isInProgressCapture
                        }
                        return !names.contains(recording.audioFileName)
                    }
                }
                return (loaded, resetInterrupted)
            } catch {
                Log.app.error("Failed to load recordings metadata: \(error.localizedDescription)")
                return nil
            }
        }()
        if let result {
            recordings = result.recordings
            if result.resetInterrupted {
                saveMetadata()
            }
            pruneExpiredRecordings()
        }
    }

    @discardableResult
    nonisolated static func resetInterruptedProcessingStates(
        in recordings: inout [Recording]
    ) -> Bool {
        var didReset = false
        for index in recordings.indices {
            switch recordings[index].status {
            case .processing:
                recordings[index].status = .unprocessed
                recordings[index].errorMessage = nil
                didReset = true
            case .recording:
                let previous = recordings[index]
                let endedAt = previous.endedAt ?? Date()
                let duration = max(0, endedAt.timeIntervalSince(previous.createdAt))
                recordings[index] = Recording(
                    id: previous.id,
                    createdAt: previous.createdAt,
                    endedAt: endedAt,
                    type: previous.type,
                    audioFileName: previous.audioFileName,
                    durationSeconds: previous.durationSeconds > 0 ? previous.durationSeconds : duration,
                    fileSizeBytes: previous.fileSizeBytes,
                    status: .needsRecovery,
                    transcriptionText: previous.transcriptionText,
                    errorMessage: nil,
                    statusDetail: nil,
                    processedAt: previous.processedAt,
                    chapters: previous.chapters,
                    sourceDevice: previous.sourceDevice,
                    translationTargetLanguageCode: previous.translationTargetLanguageCode,
                    recoverySource: previous.recoverySource ?? .orphanedSession,
                    sourceFileName: previous.sourceFileName,
                    sourceFileSizeBytes: previous.sourceFileSizeBytes,
                    remoteSource: previous.remoteSource,
                    sourceCaptionArtifacts: previous.sourceCaptionArtifacts,
                    generatedTranscriptProvenance: previous.generatedTranscriptProvenance,
                    transcriptSegments: previous.transcriptSegments,
                    title: previous.title,
                    description: previous.description,
                    transcriptHistory: previous.transcriptHistory
                )
                didReset = true
            default:
                break
            }
        }
        return didReset
    }

    private func saveMetadata() {
        let snapshot = recordings
        let url = metadataURL
        metadataWriteQueue.async {
            _ = Self.writeMetadataSnapshot(snapshot, to: url)
        }
    }

    private func saveMetadataSynchronously() -> Bool {
        let snapshot = recordings
        let url = metadataURL
        return metadataWriteQueue.sync {
            Self.writeMetadataSnapshot(snapshot, to: url)
        }
    }

    private nonisolated static func writeMetadataSnapshot(_ snapshot: [Recording], to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            Log.app.error("Failed to save recordings metadata: \(error.localizedDescription)")
            return false
        }
    }

    private nonisolated static func writeDeletionRecovery(
        _ recovery: RecordingDeletionRecovery,
        to url: URL
    ) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(recovery).write(to: url, options: .atomic)
            return true
        } catch {
            Log.app.error("Failed to save recording deletion recovery: \(error.localizedDescription)")
            return false
        }
    }

    private nonisolated static func decodeDeletionRecovery(_ data: Data) throws -> RecordingDeletionRecovery {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingDeletionRecovery.self, from: data)
    }

    private func shouldSaveRecording(type: Recording.RecordingType) -> Bool {
        let policy = SettingsStorage.shared.historyRetentionPolicy(for: type)
        guard policy.savesNewRecordings else {
            Log.app.info("Skipping recording history save because \(type.rawValue) retention is Never")
            return false
        }
        return true
    }

    private func pruneExpiredRecordingsIfEnabled() {
        pruneExpiredRecordings()
    }

    private func replaceStoredAudioFile(
        at index: Int,
        from sourceURL: URL,
        to replacementURL: URL,
        moveOnly: Bool
    ) -> URL {
        let recording = recordings[index]
        let replacementFileName = replacementURL.lastPathComponent
        let replacementFileSize: Int64 = if let attrs = try? fileManager.attributesOfItem(atPath: replacementURL.path),
                                            let size = attrs[.size] as? Int64
        {
            size
        } else {
            recording.fileSizeBytes
        }

        do {
            if moveOnly {
                try fileManager.moveItem(at: sourceURL, to: replacementURL)
            } else {
                try fileManager.removeItem(at: sourceURL)
            }

            recordings[index] = Recording(
                id: recording.id,
                createdAt: recording.createdAt,
                endedAt: recording.endedAt,
                type: recording.type,
                audioFileName: replacementFileName,
                durationSeconds: recording.durationSeconds,
                fileSizeBytes: replacementFileSize,
                status: recording.status,
                transcriptionText: recording.transcriptionText,
                errorMessage: recording.errorMessage,
                statusDetail: recording.statusDetail,
                processedAt: recording.processedAt,
                chapters: recording.chapters,
                sourceDevice: recording.sourceDevice,
                translationTargetLanguageCode: recording.translationTargetLanguageCode,
                recoverySource: recording.recoverySource,
                sourceFileName: recording.sourceFileName,
                sourceFileSizeBytes: recording.sourceFileSizeBytes,
                remoteSource: recording.remoteSource,
                sourceCaptionArtifacts: recording.sourceCaptionArtifacts,
                generatedTranscriptProvenance: recording.generatedTranscriptProvenance,
                transcriptSegments: recording.transcriptSegments,
                title: recording.title,
                description: recording.description,
                transcriptHistory: recording.transcriptHistory
            )
            saveMetadata()

            Log.app.info(
                "Recording storage optimized: \(recording.audioFileName) → \(replacementFileName), \(recording.fileSizeBytes) → \(replacementFileSize) bytes"
            )
            return replacementURL
        } catch {
            Log.app.warning("Failed to replace stored recording audio: \(error.localizedDescription)")
            if !moveOnly {
                try? fileManager.removeItem(at: replacementURL)
            }
            return sourceURL
        }
    }

    private func detectedAudioFileExtension(for audioData: Data) -> String {
        if audioData.count >= 4, String(data: audioData.prefix(4), encoding: .ascii) == "fLaC" {
            return "flac"
        }

        if audioData.count >= 12,
           String(data: audioData.prefix(4), encoding: .ascii) == "RIFF",
           String(data: audioData.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE"
        {
            return "wav"
        }

        return "wav"
    }

    private func detectedAudioFileExtension(for fileURL: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return fileURL.pathExtension.lowercased()
        }
        defer { try? handle.close() }

        let header = (try? handle.read(upToCount: 12)) ?? Data()
        return detectedAudioFileExtension(for: header)
    }
}
