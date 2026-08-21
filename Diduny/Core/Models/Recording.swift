import Foundation
import SwiftUI

struct RecordingDeviceInfo: Codable, Equatable {
    let uid: String
    let name: String
    let transportType: String
    let sampleRate: Double
    let channelCount: Int
    let wasDefaultRoute: Bool
}

/// Describes how a recording entered the library via a non-normal stop path.
/// `nil` on `Recording.recoverySource` means the recording was stopped normally.
enum RecoverySource: String, Codable {
    /// The recording was assembled from an orphaned in-progress session directory
    /// (e.g. after a crash, force-quit, or sleep interruption).
    case orphanedSession
    // Future cases: .importedFile, .crashRecovery — out of scope for M0.
}

struct TimedTranscriptSegment: Codable, Equatable {
    let startMilliseconds: Int
    let endMilliseconds: Int?
    let speaker: String?
    let text: String

    init(
        startMilliseconds: Int,
        endMilliseconds: Int? = nil,
        speaker: String? = nil,
        text: String
    ) {
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.speaker = speaker
        self.text = text
    }

    var timestampLabel: String {
        let totalSeconds = max(0, startMilliseconds) / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedText: String {
        let prefix = "[\(timestampLabel)]"
        guard let speaker = speaker?.trimmingCharacters(in: .whitespacesAndNewlines), !speaker.isEmpty else {
            return "\(prefix) \(text)"
        }
        let label = speaker.range(of: "speaker", options: [.caseInsensitive, .anchored]) == nil
            ? "Speaker \(speaker)"
            : speaker
        return "\(prefix) \(label): \(text)"
    }

    static func formattedTranscript(_ segments: [TimedTranscriptSegment]) -> String {
        segments.map(\.formattedText).joined(separator: "\n\n")
    }
}

struct TranscriptVersion: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case cloud
        case local
        case translation
    }

    let id: UUID
    let createdAt: Date
    let kind: Kind
    let provider: String?
    let modelIdentifier: String?
    let sourceLanguageCode: String?
    let targetLanguageCode: String?
    let text: String
    let segments: [TimedTranscriptSegment]?
    let provenance: GeneratedTranscriptProvenance?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: Kind,
        provider: String? = nil,
        modelIdentifier: String? = nil,
        sourceLanguageCode: String? = nil,
        targetLanguageCode: String? = nil,
        text: String,
        segments: [TimedTranscriptSegment]? = nil,
        provenance: GeneratedTranscriptProvenance? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.provider = provider
        self.modelIdentifier = modelIdentifier
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.text = text
        self.segments = segments
        self.provenance = provenance
    }

    var displayText: String {
        guard let segments, !segments.isEmpty else { return text }
        return TimedTranscriptSegment.formattedTranscript(segments)
    }
}

struct Recording: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let type: RecordingType
    let audioFileName: String
    let durationSeconds: TimeInterval
    let fileSizeBytes: Int64
    var status: ProcessingStatus
    var transcriptionText: String?
    var errorMessage: String?
    var processedAt: Date?
    var chapters: [MeetingChapter]?
    let sourceDevice: RecordingDeviceInfo?
    var translationTargetLanguageCode: String? = nil
    /// Marks a recording that originated from a recovery path rather than a normal
    /// stop; intended to drive the "Recovered" badge in the library and the
    /// detail-view notice. Once set it is preserved (never cleared), including
    /// across `RecordingsLibraryStorage.replaceStoredAudioFile`.
    var recoverySource: RecoverySource?
    /// Original Finder name for explicitly imported media. Optional so metadata
    /// written by older releases remains decodable.
    var sourceFileName: String?
    /// Byte size of the original imported media. Combined with `sourceFileName`
    /// to avoid treating unrelated same-named files as duplicates.
    var sourceFileSizeBytes: Int64?
    /// Canonical provider identity for recordings acquired from a remote source.
    /// Optional so recordings written before URL transcription remain decodable.
    var remoteSource: RemoteMediaSourceMetadata?
    /// Provider captions stay separate from Diduny's generated transcript.
    var sourceCaptionArtifacts: [TranscriptArtifact]?
    /// Identifies which Diduny provider produced `transcriptionText`.
    var generatedTranscriptProvenance: GeneratedTranscriptProvenance?
    /// Phrase-level timestamps from the generated transcript provider.
    /// Optional so recordings created by older releases remain decodable.
    var transcriptSegments: [TimedTranscriptSegment]?
    var title: String? = nil
    var description: String? = nil
    var transcriptHistory: [TranscriptVersion]? = nil

    var isYouTubeVideo: Bool {
        remoteSource?.provider == YouTubeRemoteMediaSource.provider
    }

    var libraryDisplayName: String {
        isYouTubeVideo ? "YouTube Video" : type.displayName
    }

    var libraryIconName: String {
        isYouTubeVideo ? "play.rectangle.fill" : type.iconName
    }

    var libraryBrandColor: Color {
        isYouTubeVideo ? .red : type.brandColor
    }

    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return remoteSource?.title ?? sourceFileName ?? libraryDisplayName
    }

    var resolvedTranscriptHistory: [TranscriptVersion] {
        if let transcriptHistory, !transcriptHistory.isEmpty {
            return transcriptHistory
        }
        guard let transcriptionText, !transcriptionText.isEmpty else { return [] }
        let provider = generatedTranscriptProvenance?.provider
        let kind: TranscriptVersion.Kind = if status == .translated || translationTargetLanguageCode != nil {
            .translation
        } else if provider?.localizedCaseInsensitiveContains("local") == true
            || provider?.localizedCaseInsensitiveContains("whisper") == true
        {
            .local
        } else {
            .cloud
        }
        return [TranscriptVersion(
            id: id,
            createdAt: processedAt ?? createdAt,
            kind: kind,
            provider: provider,
            targetLanguageCode: translationTargetLanguageCode,
            text: transcriptionText,
            segments: transcriptSegments,
            provenance: generatedTranscriptProvenance
        )]
    }

    var displayTranscriptText: String? {
        guard let transcriptionText, !transcriptionText.isEmpty else { return nil }
        guard let transcriptSegments, !transcriptSegments.isEmpty else { return transcriptionText }
        return TimedTranscriptSegment.formattedTranscript(transcriptSegments)
    }

    var requiresLocalTranscription: Bool {
        type == .fileTranscription
    }

    /// Nested to avoid conflict with RecoveryState.RecordingType
    enum RecordingType: String, Codable, CaseIterable {
        case voice
        case translation
        case meeting
        case meetingTranslation
        case fileTranscription

        var displayName: String {
            switch self {
            case .voice: "Voice"
            case .translation: "Translation"
            case .meeting: "Meeting"
            case .meetingTranslation: "Meeting Translation"
            case .fileTranscription: "File Transcription"
            }
        }

        var iconName: String {
            switch self {
            case .voice: "mic.fill"
            case .translation: "globe"
            case .meeting: "person.3.fill"
            case .meetingTranslation: "captions.bubble.fill"
            case .fileTranscription: "doc.fill"
            }
        }

        var shortPrefix: String {
            switch self {
            case .voice: "Transcribe"
            case .translation: "Translate"
            case .meeting: "Meeting"
            case .meetingTranslation: "Meeting Translate"
            case .fileTranscription: "File"
            }
        }

        var clipboardCopyBehavior: ClipboardCopyBehavior {
            switch self {
            case .voice, .translation, .fileTranscription:
                .cleaned
            case .meeting, .meetingTranslation:
                .raw
            }
        }

        var brandColor: Color {
            switch self {
            case .voice: Color("BrandAccentDeep")
            case .translation: .teal
            case .meeting: .orange
            case .meetingTranslation: .blue
            case .fileTranscription: .brown
            }
        }

        var isMeetingLike: Bool {
            switch self {
            case .meeting, .meetingTranslation:
                true
            case .voice, .translation, .fileTranscription:
                false
            }
        }

        var usesTranslatedStatusWhenSavedWithText: Bool {
            switch self {
            case .translation, .meetingTranslation:
                true
            case .voice, .meeting, .fileTranscription:
                false
            }
        }
    }

    enum ProcessingStatus: String, Codable {
        case unprocessed
        case processing
        case transcribed
        case translated
        case failed
        /// Audio was recovered from an interrupted session and one or more chunks
        /// were unreadable. The reported duration reflects only the intact chunks.
        case partiallyRecovered

        var displayName: String {
            switch self {
            case .unprocessed: "Unprocessed"
            case .processing: "Processing"
            case .transcribed: "Transcribed"
            case .translated: "Translated"
            case .failed: "Failed"
            case .partiallyRecovered: "Partially Recovered"
            }
        }
    }
}

struct RecordingStatistics {
    let recordingCount: Int
    let totalDurationSeconds: TimeInterval
    let voiceDurationSeconds: TimeInterval
    let translationDurationSeconds: TimeInterval
    let meetingDurationSeconds: TimeInterval
    let importedFileDurationSeconds: TimeInterval
    let youtubeDurationSeconds: TimeInterval
    let transcribedWordCount: Int
    let mediaTimeSavedSeconds: TimeInterval

    private let typingWordCount: Int
    private let typingDurationSeconds: TimeInterval

    init(recordings: [Recording]) {
        recordingCount = recordings.count
        totalDurationSeconds = recordings.reduce(0) { $0 + $1.durationSeconds }
        voiceDurationSeconds = recordings.filter { $0.type == .voice }.reduce(0) { $0 + $1.durationSeconds }
        translationDurationSeconds = recordings.filter { $0.type == .translation }.reduce(0) { $0 + $1.durationSeconds }
        meetingDurationSeconds = recordings.filter(\.type.isMeetingLike).reduce(0) { $0 + $1.durationSeconds }
        importedFileDurationSeconds = recordings
            .filter { $0.type == .fileTranscription && !$0.isYouTubeVideo }
            .reduce(0) { $0 + $1.durationSeconds }
        youtubeDurationSeconds = recordings
            .filter { $0.type == .fileTranscription && $0.isYouTubeVideo }
            .reduce(0) { $0 + $1.durationSeconds }
        transcribedWordCount = recordings.reduce(0) { $0 + Self.wordCount(in: $1.transcriptionText) }

        let typingRecordings = recordings.filter { $0.type != .fileTranscription }
        typingWordCount = typingRecordings.reduce(0) { $0 + Self.wordCount(in: $1.transcriptionText) }
        typingDurationSeconds = typingRecordings.reduce(0) { $0 + $1.durationSeconds }
        mediaTimeSavedSeconds = recordings
            .filter { $0.type == .fileTranscription && Self.hasReadableTranscript($0.transcriptionText) }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    func typingTimeSavedSeconds(wordsPerMinute: Double) -> TimeInterval {
        let typingTime = Double(typingWordCount) / max(wordsPerMinute, 1) * 60
        return max(typingTime - typingDurationSeconds, 0)
    }

    func totalTimeSavedSeconds(wordsPerMinute: Double) -> TimeInterval {
        typingTimeSavedSeconds(wordsPerMinute: wordsPerMinute) + mediaTimeSavedSeconds
    }

    private static func wordCount(in text: String?) -> Int {
        text?.split(whereSeparator: \.isWhitespace).count ?? 0
    }

    private static func hasReadableTranscript(_ text: String?) -> Bool {
        !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
