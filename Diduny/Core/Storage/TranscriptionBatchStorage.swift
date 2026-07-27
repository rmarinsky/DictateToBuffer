import Foundation

enum TranscriptionBatchStatus: String, Codable {
    case processing = "Processing"
    case completed = "Completed"
    case completedWithIssues = "Completed with Issues"
}

struct TranscriptionBatch: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var description: String
    let createdAt: Date
    var isProcessingClosed: Bool
    var recordingIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        createdAt: Date = Date(),
        isProcessingClosed: Bool = false,
        recordingIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.isProcessingClosed = isProcessingClosed
        self.recordingIDs = recordingIDs
    }

    func status(in recordings: [Recording]) -> TranscriptionBatchStatus {
        guard isProcessingClosed else { return .processing }
        let byID = Dictionary(uniqueKeysWithValues: recordings.map { ($0.id, $0) })
        return recordingIDs.allSatisfy { id in
            guard let recording = byID[id] else { return false }
            return recording.status == .transcribed || recording.status == .translated
        } ? .completed : .completedWithIssues
    }

    func matches(_ query: String, recordings: [Recording]) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        if name.localizedCaseInsensitiveContains(normalized)
            || description.localizedCaseInsensitiveContains(normalized)
        {
            return true
        }
        let memberIDs = Set(recordingIDs)
        return recordings.contains { recording in
            memberIDs.contains(recording.id)
                && [
                    recording.sourceFileName,
                    recording.remoteSource?.title,
                    recording.libraryDisplayName,
                    recording.transcriptionText,
                ].compactMap { $0 }.contains {
                    $0.localizedCaseInsensitiveContains(normalized)
                }
        }
    }

    func markdown(recordings: [Recording]) -> String {
        let byID = Dictionary(uniqueKeysWithValues: recordings.map { ($0.id, $0) })
        return recordingIDs.compactMap { id -> String? in
            guard let recording = byID[id] else { return nil }
            let title = recording.remoteSource?.title
                ?? recording.sourceFileName
                ?? recording.libraryDisplayName
            let body = recording.displayTranscriptText
                ?? "[Transcript unavailable — \(recording.status.displayName)]"
            return "# \(title)\n\nSource: \(recording.libraryDisplayName)\n\n\(body)"
        }.joined(separator: "\n\n")
    }
}

@Observable
@MainActor
final class TranscriptionBatchStorage {
    enum StorageError: Error {
        case batchNotFound
        case membershipClosed
    }

    static let shared: TranscriptionBatchStorage = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "Diduny"
        return try! TranscriptionBatchStorage(
            baseDirectory: appSupport.appendingPathComponent(bundleID)
        )
    }()

    private(set) var batches: [TranscriptionBatch]
    private let metadataURL: URL

    init(baseDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        metadataURL = baseDirectory.appendingPathComponent("transcription_batches.json")
        guard let data = try? Data(contentsOf: metadataURL) else {
            batches = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        batches = try decoder.decode([TranscriptionBatch].self, from: data)
        batches.sort { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func create(
        name: String,
        description: String = "",
        recordingIDs: [UUID],
        createdAt: Date = Date()
    ) throws -> TranscriptionBatch {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let batch = TranscriptionBatch(
            name: trimmedName.isEmpty ? Self.defaultName(for: createdAt) : trimmedName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            recordingIDs: unique(recordingIDs)
        )
        batches.insert(batch, at: 0)
        try save()
        return batch
    }

    func update(batchID: UUID, name: String, description: String) throws {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else {
            throw StorageError.batchNotFound
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        batches[index].name = trimmedName.isEmpty
            ? Self.defaultName(for: batches[index].createdAt)
            : trimmedName
        batches[index].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        try save()
    }

    func addRecordingIDs(_ recordingIDs: [UUID], to batchID: UUID) throws {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else {
            throw StorageError.batchNotFound
        }
        guard !batches[index].isProcessingClosed else {
            throw StorageError.membershipClosed
        }
        batches[index].recordingIDs = unique(batches[index].recordingIDs + recordingIDs)
        try save()
    }

    func replaceRecordingIDs(_ recordingIDs: [UUID], in batchID: UUID) throws {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else {
            throw StorageError.batchNotFound
        }
        batches[index].recordingIDs = unique(recordingIDs)
        try save()
    }

    func close(batchID: UUID) throws {
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else {
            throw StorageError.batchNotFound
        }
        batches[index].isProcessingClosed = true
        try save()
    }

    func removeRecordingReferences(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        for index in batches.indices {
            batches[index].recordingIDs.removeAll(where: ids.contains)
        }
        try save()
    }

    @discardableResult
    func delete(batchID: UUID) throws -> Set<UUID> {
        guard let batch = batches.first(where: { $0.id == batchID }) else {
            throw StorageError.batchNotFound
        }
        let affected = Set(batch.recordingIDs)
        batches.removeAll { $0.id == batchID }
        for index in batches.indices {
            batches[index].recordingIDs.removeAll(where: affected.contains)
        }
        try save()
        return affected
    }

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(batches).write(to: metadataURL, options: .atomic)
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MMM d, yyyy, HH:mm"
        return "Batch — \(formatter.string(from: date))"
    }
}
