@testable import Diduny
import XCTest

/// Tests for the RLR-M0 data-model additions:
///   - `RecoverySource` enum + `Recording.recoverySource` property
///   - `Recording.ProcessingStatus.partiallyRecovered` case
///   - optional `Recording.translationTargetLanguageCode`
///
/// The primary concerns are:
///   1. Backward compatibility — JSON written before M0 (no `recoverySource` key,
///      no `partiallyRecovered` status) must decode without error.
///   2. Round-trip fidelity for the new fields.
///   3. Exhaustive switch coverage for `ProcessingStatus` (compiler-enforced).
final class RecordingModelMigrationTests: XCTestCase {
    // MARK: - Helpers

    private let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let iso8601Encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// A minimal JSON object that represents a Recording saved before RLR-M0.
    /// It intentionally omits `recoverySource` and uses only pre-M0 status values.
    private let legacyJSON = """
    [
      {
        "id": "12345678-1234-1234-1234-123456789ABC",
        "createdAt": "2025-11-01T10:00:00Z",
        "type": "meeting",
        "audioFileName": "12345678-1234-1234-1234-123456789ABC.wav",
        "durationSeconds": 3600.0,
        "fileSizeBytes": 675000000,
        "status": "transcribed",
        "transcriptionText": "Hello world.",
        "processedAt": "2025-11-01T11:00:00Z"
      }
    ]
    """

    // MARK: - 1. Backward compatibility

    func test_legacyJSON_decodesWithoutError() throws {
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let recordings = try iso8601.decode([Recording].self, from: data)
        XCTAssertEqual(recordings.count, 1)
    }

    func test_legacyJSON_recoverySourceIsNil() throws {
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let recordings = try iso8601.decode([Recording].self, from: data)
        XCTAssertNil(recordings[0].recoverySource,
                     "recordings from before M0 must have recoverySource == nil")
    }

    func test_legacyJSON_translationTargetLanguageCodeIsNil() throws {
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let recordings = try iso8601.decode([Recording].self, from: data)
        XCTAssertNil(recordings[0].translationTargetLanguageCode)
    }

    func test_legacyJSON_sourceFileNameIsNil() throws {
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let recordings = try iso8601.decode([Recording].self, from: data)
        XCTAssertNil(recordings[0].sourceFileName)
        XCTAssertNil(recordings[0].sourceFileSizeBytes)
        XCTAssertNil(recordings[0].remoteSource)
        XCTAssertNil(recordings[0].sourceCaptionArtifacts)
        XCTAssertNil(recordings[0].generatedTranscriptProvenance)
        XCTAssertNil(recordings[0].transcriptSegments)
    }

    func test_legacyJSON_originalFieldsIntact() throws {
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let recording = try iso8601.decode([Recording].self, from: data)[0]

        XCTAssertEqual(recording.id.uuidString, "12345678-1234-1234-1234-123456789ABC")
        XCTAssertEqual(recording.type, .meeting)
        XCTAssertEqual(recording.audioFileName, "12345678-1234-1234-1234-123456789ABC.wav")
        XCTAssertEqual(recording.durationSeconds, 3600.0, accuracy: 0.001)
        XCTAssertEqual(recording.fileSizeBytes, 675_000_000)
        XCTAssertEqual(recording.status, .transcribed)
        XCTAssertEqual(recording.transcriptionText, "Hello world.")
    }

    func test_legacyJSON_surfacesScalarTranscriptAsHistoryWithoutDataLoss() throws {
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let recording = try iso8601.decode([Recording].self, from: data)[0]

        let version = try XCTUnwrap(recording.resolvedTranscriptHistory.first)
        XCTAssertEqual(recording.resolvedTranscriptHistory.count, 1)
        XCTAssertEqual(version.id, recording.id)
        XCTAssertEqual(version.createdAt, recording.processedAt)
        XCTAssertEqual(version.kind, .cloud)
        XCTAssertEqual(version.text, "Hello world.")
    }

    // MARK: - 2. Round-trip

    func test_roundTrip_orphanedSession_partiallyRecovered() throws {
        let original = try Recording(
            id: XCTUnwrap(UUID(uuidString: "AABBCCDD-AABB-CCDD-AABB-CCDDAABBCCDD")),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            type: .meeting,
            audioFileName: "AABBCCDD-AABB-CCDD-AABB-CCDDAABBCCDD.flac",
            durationSeconds: 2400.0,
            fileSizeBytes: 48_000_000,
            status: .partiallyRecovered,
            transcriptionText: nil,
            errorMessage: nil,
            processedAt: nil,
            chapters: nil,
            sourceDevice: nil,
            recoverySource: .orphanedSession
        )

        let data = try iso8601Encoder.encode([original])
        let decoded = try iso8601.decode([Recording].self, from: data)[0]

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.status, .partiallyRecovered)
        XCTAssertEqual(decoded.recoverySource, .orphanedSession)
        XCTAssertEqual(decoded.durationSeconds, original.durationSeconds, accuracy: 0.001)
        XCTAssertNil(decoded.transcriptionText)
    }

    func test_roundTrip_preservesRemoteSourceAndSeparateTranscriptArtifacts() throws {
        let remoteSource = try RemoteMediaSourceMetadata(
            provider: YouTubeRemoteMediaSource.provider,
            mediaID: "dQw4w9WgXcQ",
            canonicalURL: XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")),
            title: "A video",
            channelName: "A channel"
        )
        let captions = TranscriptArtifact(
            text: "Source caption text",
            languageCode: "uk",
            provenance: .youtubeAutomatic
        )
        let generated = GeneratedTranscriptProvenance(provider: "cloud")
        let segments = [
            TimedTranscriptSegment(
                startMilliseconds: 1200,
                endMilliseconds: 2300,
                speaker: "1",
                text: "Generated transcript"
            )
        ]
        let original = Recording(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            type: .fileTranscription,
            audioFileName: "remote.m4a",
            durationSeconds: 120,
            fileSizeBytes: 42,
            status: .transcribed,
            transcriptionText: "Generated transcript",
            sourceDevice: nil,
            remoteSource: remoteSource,
            sourceCaptionArtifacts: [captions],
            generatedTranscriptProvenance: generated,
            transcriptSegments: segments
        )

        let data = try iso8601Encoder.encode([original])
        let decoded = try iso8601.decode([Recording].self, from: data)[0]

        XCTAssertEqual(decoded.remoteSource, remoteSource)
        XCTAssertEqual(decoded.sourceCaptionArtifacts, [captions])
        XCTAssertEqual(decoded.generatedTranscriptProvenance, generated)
        XCTAssertEqual(decoded.transcriptSegments, segments)
        XCTAssertEqual(decoded.transcriptionText, "Generated transcript")
    }

    func test_displayTranscriptText_includesStoredPhraseTimestamps() {
        let recording = Recording(
            id: UUID(),
            createdAt: Date(),
            type: .fileTranscription,
            audioFileName: "video.m4a",
            durationSeconds: 3700,
            fileSizeBytes: 42,
            status: .transcribed,
            transcriptionText: "First phrase. Later phrase.",
            sourceDevice: nil,
            transcriptSegments: [
                TimedTranscriptSegment(startMilliseconds: 1200, endMilliseconds: 2300, text: "First phrase."),
                TimedTranscriptSegment(
                    startMilliseconds: 3_661_000,
                    endMilliseconds: 3_662_000,
                    text: "Later phrase."
                )
            ]
        )

        XCTAssertEqual(
            recording.displayTranscriptText,
            "[00:01] First phrase.\n\n[1:01:01] Later phrase."
        )
    }

    func test_displayTranscriptText_includesStoredSpeakerLabels() {
        let recording = Recording(
            id: UUID(),
            createdAt: Date(),
            type: .meeting,
            audioFileName: "meeting.flac",
            durationSeconds: 10,
            fileSizeBytes: 42,
            status: .transcribed,
            transcriptionText: "Hello. Hi.",
            sourceDevice: nil,
            transcriptSegments: [
                TimedTranscriptSegment(
                    startMilliseconds: 1_200,
                    endMilliseconds: 2_300,
                    speaker: "1",
                    text: "Hello."
                ),
                TimedTranscriptSegment(
                    startMilliseconds: 4_500,
                    endMilliseconds: 5_100,
                    speaker: "2",
                    text: "Hi."
                )
            ]
        )

        XCTAssertEqual(
            recording.displayTranscriptText,
            "[00:01] Speaker 1: Hello.\n\n[00:04] Speaker 2: Hi."
        )
        XCTAssertEqual(
            recording.resolvedTranscriptHistory.first?.displayText,
            "[00:01] Speaker 1: Hello.\n\n[00:04] Speaker 2: Hi."
        )
    }

    func test_roundTrip_nilRecoverySource_normalStop() throws {
        let original = Recording(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_100_000),
            type: .voice,
            audioFileName: "voice.wav",
            durationSeconds: 12.5,
            fileSizeBytes: 220_500,
            status: .transcribed,
            transcriptionText: "Test text.",
            errorMessage: nil,
            processedAt: Date(timeIntervalSince1970: 1_700_100_015),
            chapters: nil,
            sourceDevice: nil,
            recoverySource: nil
        )

        let data = try iso8601Encoder.encode([original])
        let decoded = try iso8601.decode([Recording].self, from: data)[0]

        XCTAssertEqual(decoded.status, .transcribed)
        XCTAssertNil(decoded.recoverySource)
    }

    func test_roundTrip_importedSourceFileName() throws {
        let original = Recording(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_100_000),
            type: .fileTranscription,
            audioFileName: "import.m4a",
            durationSeconds: 30,
            fileSizeBytes: 4096,
            status: .transcribed,
            transcriptionText: "Imported transcript",
            sourceDevice: nil,
            sourceFileName: "Product walkthrough.mov",
            sourceFileSizeBytes: 81920
        )

        let data = try iso8601Encoder.encode([original])
        let decoded = try iso8601.decode([Recording].self, from: data)[0]

        XCTAssertEqual(decoded.sourceFileName, "Product walkthrough.mov")
        XCTAssertEqual(decoded.sourceFileSizeBytes, 81920)
    }

    func test_roundTrip_preservesEditableDetailsAndTranscriptHistory() throws {
        let version = TranscriptVersion(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_100_100),
            kind: .translation,
            provider: "cloud",
            sourceLanguageCode: "en",
            targetLanguageCode: "es",
            text: "Hola"
        )
        let original = Recording(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_100_000),
            type: .fileTranscription,
            audioFileName: "interview.m4a",
            durationSeconds: 30,
            fileSizeBytes: 4096,
            status: .translated,
            transcriptionText: "Hola",
            sourceDevice: nil,
            title: "Customer interview",
            description: "Onboarding research",
            transcriptHistory: [version]
        )

        let data = try iso8601Encoder.encode([original])
        let decoded = try iso8601.decode([Recording].self, from: data)[0]

        XCTAssertEqual(decoded.title, "Customer interview")
        XCTAssertEqual(decoded.description, "Onboarding research")
        XCTAssertEqual(decoded.displayTitle, "Customer interview")
        XCTAssertEqual(decoded.resolvedTranscriptHistory, [version])
    }

    func test_interruptedProcessingResetsToUnprocessedAfterLoad() {
        var recordings = [
            Recording(
                id: UUID(),
                createdAt: Date(),
                type: .fileTranscription,
                audioFileName: "prepared.m4a",
                durationSeconds: 30,
                fileSizeBytes: 4096,
                status: .processing,
                errorMessage: "Interrupted",
                sourceDevice: nil
            ),
            Recording(
                id: UUID(),
                createdAt: Date(),
                type: .fileTranscription,
                audioFileName: "complete.m4a",
                durationSeconds: 30,
                fileSizeBytes: 4096,
                status: .transcribed,
                transcriptionText: "Done",
                sourceDevice: nil
            )
        ]

        XCTAssertTrue(RecordingsLibraryStorage.resetInterruptedProcessingStates(in: &recordings))
        XCTAssertEqual(recordings[0].status, .unprocessed)
        XCTAssertNil(recordings[0].errorMessage)
        XCTAssertEqual(recordings[1].status, .transcribed)
        XCTAssertEqual(recordings[1].transcriptionText, "Done")
    }

    func test_meetingTranslationType_roundTripsAndUsesMeetingBucket() throws {
        let original = Recording(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_200_000),
            type: .meetingTranslation,
            audioFileName: "meeting-translation.flac",
            durationSeconds: 120.0,
            fileSizeBytes: 2048,
            status: .translated,
            transcriptionText: "Translated meeting.",
            errorMessage: nil,
            processedAt: Date(timeIntervalSince1970: 1_700_200_120),
            chapters: nil,
            sourceDevice: nil,
            translationTargetLanguageCode: "fr",
            recoverySource: nil
        )

        let data = try iso8601Encoder.encode([original])
        let decoded = try iso8601.decode([Recording].self, from: data)[0]

        XCTAssertEqual(decoded.type, .meetingTranslation)
        XCTAssertEqual(decoded.translationTargetLanguageCode, "fr")
        XCTAssertTrue(decoded.type.isMeetingLike)
        XCTAssertEqual(decoded.type.clipboardCopyBehavior, .raw)
        XCTAssertTrue(decoded.type.usesTranslatedStatusWhenSavedWithText)
    }

    // MARK: - 3. Exhaustive switch coverage (compiler-enforced)

    /// This test's body must enumerate every `ProcessingStatus` case.
    /// If a future PR adds a case without updating this switch the compiler
    /// will fail the build — that is the intended behavior.
    func test_processingStatus_switchIsExhaustive() {
        let allCases: [Recording.ProcessingStatus] = [
            .unprocessed,
            .processing,
            .transcribed,
            .translated,
            .failed,
            .partiallyRecovered,
            .recording,
            .needsRecovery
        ]

        for status in allCases {
            switch status {
            case .unprocessed:
                _ = status
            case .processing:
                _ = status
            case .transcribed:
                _ = status
            case .translated:
                _ = status
            case .failed:
                _ = status
            case .partiallyRecovered:
                _ = status
            case .recording:
                _ = status
            case .needsRecovery:
                _ = status
            }
        }
        // If this compiles, all cases are handled.
        XCTAssertEqual(allCases.count, 8)
    }

    // MARK: - 4. RecoverySource raw-value stability

    func test_recoverySource_rawValues() {
        // Raw-value strings are persisted to disk — must never change.
        XCTAssertEqual(RecoverySource.orphanedSession.rawValue, "orphanedSession")
    }
}
