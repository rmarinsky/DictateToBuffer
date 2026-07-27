@testable import Diduny
import XCTest

@MainActor
final class TranscriptionBatchStorageTests: XCTestCase {
    private func makeRecording(
        id: UUID = UUID(),
        title: String,
        status: Recording.ProcessingStatus = .transcribed,
        transcript: String? = "Transcript"
    ) -> Recording {
        Recording(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            type: .fileTranscription,
            audioFileName: "\(id).m4a",
            durationSeconds: 60,
            fileSizeBytes: 42,
            status: status,
            transcriptionText: transcript,
            sourceDevice: nil,
            sourceFileName: title
        )
    }

    func test_storeRoundTripPreservesOrderedMembershipAndEditableMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionBatchStorageTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstID = UUID()
        let secondID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        let store = try TranscriptionBatchStorage(baseDirectory: directory)
        let batch = try store.create(
            name: "  ",
            description: "Initial",
            recordingIDs: [firstID, secondID],
            createdAt: createdAt
        )
        XCTAssertTrue(batch.name.hasPrefix("Batch — "))
        XCTAssertTrue(batch.name.contains("2023"))
        try store.update(batchID: batch.id, name: "Research", description: "Updated")
        try store.close(batchID: batch.id)

        let reloaded = try TranscriptionBatchStorage(baseDirectory: directory)
        let persisted = try XCTUnwrap(reloaded.batches.first)
        XCTAssertEqual(persisted.name, "Research")
        XCTAssertEqual(persisted.description, "Updated")
        XCTAssertEqual(persisted.createdAt, createdAt)
        XCTAssertEqual(persisted.recordingIDs, [firstID, secondID])
        XCTAssertTrue(persisted.isProcessingClosed)
    }

    func test_batchDerivesStatusSearchAndMarkdownFromCurrentRecordings() throws {
        let completed = makeRecording(title: "Quarterly planning", transcript: "Revenue grew")
        let failed = makeRecording(title: "Customer call", status: .failed, transcript: nil)
        let batch = TranscriptionBatch(
            name: "Planning",
            description: "Board preparation",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isProcessingClosed: true,
            recordingIDs: [completed.id, failed.id]
        )
        let recordings = [completed, failed]

        XCTAssertEqual(batch.status(in: recordings), .completedWithIssues)
        XCTAssertTrue(batch.matches("revenue", recordings: recordings))
        XCTAssertTrue(batch.matches("customer", recordings: recordings))
        XCTAssertEqual(
            batch.markdown(recordings: recordings),
            "# Quarterly planning\n\nSource: File Transcription\n\nRevenue grew\n\n# Customer call\n\nSource: File Transcription\n\n[Transcript unavailable — Failed]"
        )
    }

    func test_removingRecordingCleansEveryBatchReference() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionBatchStorageTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sharedID = UUID()
        let store = try TranscriptionBatchStorage(baseDirectory: directory)
        _ = try store.create(name: "One", recordingIDs: [sharedID])
        _ = try store.create(name: "Two", recordingIDs: [UUID(), sharedID])

        try store.removeRecordingReferences(Set([sharedID]))

        XCTAssertTrue(store.batches.allSatisfy { !$0.recordingIDs.contains(sharedID) })
        let reloaded = try TranscriptionBatchStorage(baseDirectory: directory)
        XCTAssertTrue(reloaded.batches.allSatisfy { !$0.recordingIDs.contains(sharedID) })
    }

    func test_deleteReturnsAllAffectedRecordingIDsAndRemovesSharedReferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionBatchStorageTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sharedID = UUID()
        let ownedID = UUID()
        let store = try TranscriptionBatchStorage(baseDirectory: directory)
        let target = try store.create(name: "Target", recordingIDs: [ownedID, sharedID])
        _ = try store.create(name: "Other", recordingIDs: [sharedID])

        let affected = try store.delete(batchID: target.id)

        XCTAssertEqual(affected, Set([ownedID, sharedID]))
        XCTAssertEqual(store.batches.count, 1)
        XCTAssertEqual(store.batches[0].recordingIDs, [])
    }
}
