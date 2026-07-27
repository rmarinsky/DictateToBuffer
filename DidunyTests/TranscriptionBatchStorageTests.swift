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

    func test_storeRoundTripPreservesFailedWorkForRestartRetry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionBatchStorageTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try YouTubeRemoteMediaSource.normalize("https://youtu.be/dQw4w9WgXcQ")
        var item = BatchTranscriptionItem(remoteSource: source)
        item.status = .failed
        item.errorMessage = "Network unavailable"

        let store = try TranscriptionBatchStorage(baseDirectory: directory)
        let batch = try store.create(name: "Retry", recordingIDs: [])
        try store.replaceWorkItems([item], in: batch.id)
        try store.close(batchID: batch.id)

        let persisted = try XCTUnwrap(
            try TranscriptionBatchStorage(baseDirectory: directory).batches.first
        )
        XCTAssertEqual(persisted.workItems, [item])
        XCTAssertEqual(persisted.status(in: []), .completedWithIssues)
        XCTAssertTrue(persisted.markdown(recordings: []).contains("Network unavailable"))
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

    func test_markdownKeepsFailedAndCompletedWorkItemOrder() throws {
        let completed = makeRecording(title: "Second", transcript: "Done")
        var failedItem = BatchTranscriptionItem(sourceURL: URL(fileURLWithPath: "/tmp/first.m4a"))
        failedItem.status = .failed
        failedItem.errorMessage = "Failed first"
        var completedItem = BatchTranscriptionItem(sourceURL: URL(fileURLWithPath: "/tmp/second.m4a"))
        completedItem.status = .completed
        completedItem.recordingID = completed.id
        let batch = TranscriptionBatch(
            name: "Ordered",
            isProcessingClosed: true,
            recordingIDs: [completed.id],
            workItems: [failedItem, completedItem]
        )

        let markdown = batch.markdown(recordings: [completed])
        XCTAssertLessThan(
            try XCTUnwrap(markdown.range(of: "first.m4a")?.lowerBound),
            try XCTUnwrap(markdown.range(of: "Second")?.lowerBound)
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
        let other = try store.create(name: "Other", recordingIDs: [sharedID])
        var sharedItem = BatchTranscriptionItem(sourceURL: URL(fileURLWithPath: "/tmp/shared.m4a"))
        sharedItem.recordingID = sharedID
        try store.replaceWorkItems([sharedItem], in: other.id)

        let affected = try store.delete(batchID: target.id)

        XCTAssertEqual(affected, Set([ownedID, sharedID]))
        XCTAssertEqual(store.batches.count, 1)
        XCTAssertEqual(store.batches[0].recordingIDs, [])
        XCTAssertEqual(store.batches[0].workItems, [])
    }

    func test_recordingAndBatchDeletionStayReferentiallyConsistent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionBatchStorageTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let batchStore = try TranscriptionBatchStorage(baseDirectory: directory)
        let recordingStore = RecordingsLibraryStorage(
            baseDirectory: directory,
            batchStorage: batchStore
        )
        let firstID = try XCTUnwrap(recordingStore.saveRecording(
            audioData: Data("first".utf8),
            type: .fileTranscription,
            duration: 1,
            transcriptionText: "First",
            forceSave: true
        ))
        let secondID = try XCTUnwrap(recordingStore.saveRecording(
            audioData: Data("second".utf8),
            type: .fileTranscription,
            duration: 1,
            transcriptionText: "Second",
            forceSave: true
        ))
        let target = try batchStore.create(name: "Target", recordingIDs: [firstID, secondID])
        _ = try batchStore.create(name: "Other", recordingIDs: [secondID])

        recordingStore.deleteRecording(try XCTUnwrap(
            recordingStore.recordings.first(where: { $0.id == firstID })
        ))
        XCTAssertTrue(batchStore.batches.allSatisfy { !$0.recordingIDs.contains(firstID) })

        recordingStore.deleteBatch(target)
        XCTAssertTrue(recordingStore.recordings.isEmpty)
        XCTAssertEqual(batchStore.batches.count, 1)
        XCTAssertTrue(batchStore.batches[0].recordingIDs.isEmpty)
    }
}
