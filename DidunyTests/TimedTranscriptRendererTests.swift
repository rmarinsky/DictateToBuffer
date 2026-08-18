@testable import Diduny
import XCTest

/// Copying a meeting transcript must hand over the same text the detail view shows:
/// timestamps plus speaker labels, not the flattened plain transcript.
final class TimedTranscriptRendererTests: XCTestCase {
    private func segment(
        startMilliseconds: Int,
        speaker: String?,
        text: String
    ) -> TimedTranscriptSegment {
        TimedTranscriptSegment(
            startMilliseconds: startMilliseconds,
            endMilliseconds: startMilliseconds + 1000,
            speaker: speaker,
            text: text
        )
    }

    func test_renderIncludesTimestampsAndSpeakerLabels() {
        let rendered = TimedTranscriptRenderer.render(
            segments: [
                segment(startMilliseconds: 0, speaker: "1", text: "Hello team."),
                segment(startMilliseconds: 65_000, speaker: "2", text: "Hi there.")
            ],
            fallbackText: "Hello team. Hi there."
        )

        XCTAssertEqual(rendered, "[00:00] Speaker 1: Hello team.\n\n[01:05] Speaker 2: Hi there.")
    }

    func test_renderKeepsProviderSuppliedSpeakerNameAsIs() {
        let rendered = TimedTranscriptRenderer.render(
            segments: [segment(startMilliseconds: 3_600_000, speaker: "Speaker A", text: "Wrapping up.")],
            fallbackText: "Wrapping up."
        )

        XCTAssertEqual(rendered, "[1:00:00] Speaker A: Wrapping up.")
    }

    func test_renderOmitsSpeakerPrefixWhenDiarizationIsMissing() {
        let rendered = TimedTranscriptRenderer.render(
            segments: [
                segment(startMilliseconds: 2000, speaker: nil, text: "Solo note."),
                segment(startMilliseconds: 4000, speaker: "   ", text: "Blank speaker.")
            ],
            fallbackText: "Solo note. Blank speaker."
        )

        XCTAssertEqual(rendered, "[00:02] Solo note.\n\n[00:04] Blank speaker.")
    }

    func test_renderFallsBackToPlainTextWithoutSegments() {
        XCTAssertEqual(
            TimedTranscriptRenderer.render(segments: nil, fallbackText: "Plain transcript."),
            "Plain transcript."
        )
        XCTAssertEqual(
            TimedTranscriptRenderer.render(segments: [], fallbackText: "Plain transcript."),
            "Plain transcript."
        )
    }

    func test_transcriptVersionDisplayTextMatchesRenderedSegments() {
        let version = TranscriptVersion(
            kind: .cloud,
            text: "Hello team.",
            segments: [segment(startMilliseconds: 0, speaker: "1", text: "Hello team.")]
        )

        XCTAssertEqual(version.displayText, "[00:00] Speaker 1: Hello team.")
    }

    func test_recordingDisplayTranscriptTextUsesSpeakerLabels() {
        var recording = Recording(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            type: .meeting,
            audioFileName: "meeting.wav",
            durationSeconds: 120,
            fileSizeBytes: 42,
            status: .transcribed,
            transcriptionText: "Hello team. Hi there.",
            sourceDevice: nil
        )
        recording.transcriptSegments = [
            segment(startMilliseconds: 0, speaker: "1", text: "Hello team."),
            segment(startMilliseconds: 5000, speaker: "2", text: "Hi there.")
        ]

        XCTAssertEqual(
            recording.displayTranscriptText,
            "[00:00] Speaker 1: Hello team.\n\n[00:05] Speaker 2: Hi there."
        )
    }
}
