@testable import Diduny
import XCTest

@MainActor
final class MeetingLiveLibraryRowTests: XCTestCase {
    private var directory: URL!
    private var storage: RecordingsLibraryStorage!

    override func setUp() async throws {
        try await super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingLiveLibraryRowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let batchStorage = try TranscriptionBatchStorage(baseDirectory: directory)
        storage = RecordingsLibraryStorage(baseDirectory: directory, batchStorage: batchStorage)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    func test_beginMeetingRecording_createsRecordingStatusRowWithoutAudio() {
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let result = storage.beginMeetingRecording(id: id, type: .meeting, createdAt: started)
        XCTAssertEqual(result, id)

        let row = try! XCTUnwrap(storage.recordings.first(where: { $0.id == id }))
        XCTAssertEqual(row.status, .recording)
        XCTAssertEqual(row.createdAt, started)
        XCTAssertNil(row.endedAt)
        XCTAssertTrue(row.audioFileName.isEmpty)
        XCTAssertFalse(storage.hasPlayableAudio(for: row))
    }

    func test_finalizeInProgressRecording_attachesAudioAndEndedAt() throws {
        let id = UUID()
        _ = storage.beginMeetingRecording(id: id, type: .meeting)

        let wav = directory.appendingPathComponent("source.wav")
        try Data("RIFF....WAVEfmt ".utf8).write(to: wav)

        let ended = Date()
        let ok = storage.finalizeInProgressRecording(
            id: id,
            audioURL: wav,
            duration: 42,
            endedAt: ended,
            status: .processing,
            forceSave: true
        )
        XCTAssertTrue(ok)

        let row = try XCTUnwrap(storage.recordings.first(where: { $0.id == id }))
        XCTAssertEqual(row.status, .processing)
        XCTAssertEqual(row.durationSeconds, 42, accuracy: 0.001)
        XCTAssertEqual(row.endedAt?.timeIntervalSince1970 ?? 0, ended.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertFalse(row.audioFileName.isEmpty)
        XCTAssertTrue(storage.hasPlayableAudio(for: row))
    }

    func test_resetInterruptedProcessingStates_promotesRecordingToNeedsRecovery() {
        var recordings = [
            Recording(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                endedAt: nil,
                type: .meeting,
                audioFileName: "",
                durationSeconds: 0,
                fileSizeBytes: 0,
                status: .recording,
                sourceDevice: nil
            )
        ]
        let didReset = RecordingsLibraryStorage.resetInterruptedProcessingStates(in: &recordings)
        XCTAssertTrue(didReset)
        XCTAssertEqual(recordings[0].status, .needsRecovery)
        XCTAssertEqual(recordings[0].recoverySource, .orphanedSession)
        XCTAssertNotNil(recordings[0].endedAt)
    }

    func test_legacyJSON_endedAtIsNil() throws {
        let legacyJSON = """
        [
          {
            "id": "12345678-1234-1234-1234-123456789ABC",
            "createdAt": "2025-11-01T10:00:00Z",
            "type": "meeting",
            "audioFileName": "12345678-1234-1234-1234-123456789ABC.wav",
            "durationSeconds": 3600.0,
            "fileSizeBytes": 675000000,
            "status": "transcribed"
          }
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let recordings = try decoder.decode([Recording].self, from: data)
        XCTAssertNil(recordings[0].endedAt)
        XCTAssertNil(recordings[0].statusDetail)
        let resolvedEndedAt = try XCTUnwrap(recordings[0].resolvedEndedAt)
        XCTAssertEqual(
            resolvedEndedAt.timeIntervalSince1970,
            recordings[0].createdAt.addingTimeInterval(3600).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func test_markNeedsRecovery_setsStatusAndSource() {
        let id = UUID()
        _ = storage.beginMeetingRecording(id: id, type: .meetingTranslation)
        let ended = Date()
        XCTAssertTrue(storage.markNeedsRecovery(id: id, endedAt: ended, durationSeconds: 12))
        let row = try! XCTUnwrap(storage.recordings.first(where: { $0.id == id }))
        XCTAssertEqual(row.status, .needsRecovery)
        XCTAssertEqual(row.recoverySource, .orphanedSession)
        XCTAssertEqual(row.durationSeconds, 12, accuracy: 0.001)
    }
}
