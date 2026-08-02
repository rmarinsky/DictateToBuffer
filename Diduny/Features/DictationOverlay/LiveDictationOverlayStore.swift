import Foundation
import Observation

enum LiveDictationOverlayPhase: Equatable {
    case starting
    case recording
    case finalizing
    case processing
    case pasted
    case error(String)
    case info(String)
}

@Observable
@MainActor
final class LiveDictationOverlayStore {
    var mode: RecordingMode = .voice
    var phase: LiveDictationOverlayPhase = .starting
    var connectionStatus: RealtimeConnectionStatus = .disconnected
    var audioLevel: Float = 0
    var startedAt = Date()
    var finalText = ""
    var provisionalText = ""
    var copiedAt: Date?

    private var fallbackFinalText = ""
    private var fallbackProvisionalText = ""
    private let meetingTranscript = LiveTranscriptStore()

    var title: String {
        switch mode {
        case .voice:
            "Transcribing"
        case .translation:
            "Translating"
        case .meeting:
            "Recording meeting"
        case .meetingTranslation:
            "Translating meeting"
        case .fileTranscription:
            "File Transcription"
        }
    }

    var statusText: String {
        switch phase {
        case .starting:
            "Starting"
        case .recording:
            switch connectionStatus {
            case .connected:
                "Recording live"
            case .connecting:
                "Connecting"
            case .reconnecting:
                "Reconnecting"
            case .failed:
                "Recording offline"
            case .disconnected:
                "Recording"
            }
        case .finalizing:
            "Finalizing"
        case .processing:
            "Formatting"
        case .pasted:
            "Complete"
        case let .error(message):
            message
        case let .info(message):
            message
        }
    }

    var visibleText: String {
        bestText(includeProvisional: true)
    }

    var displayText: String {
        guard mode == .meeting else { return visibleText }
        let structuredText = meetingTranscript.finalTranscriptText
        guard !structuredText.isEmpty else { return visibleText }

        let provisional = meetingTranscript.provisionalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provisional.isEmpty else { return structuredText }

        let speaker = meetingTranscript.provisionalSpeaker.map { "Speaker \($0): " } ?? ""
        return "\(structuredText)\n\n\(speaker)\(provisional)"
    }

    var hasText: Bool {
        !displayText.isEmpty
    }

    var canStop: Bool {
        phase == .recording || phase == .starting
    }

    var providerLabel: String {
        let provider: TranscriptionProvider = switch mode {
        case .translation, .meetingTranslation:
            SettingsStorage.shared.effectiveTranslationProvider
        case .voice, .meeting, .fileTranscription:
            SettingsStorage.shared.effectiveTranscriptionProvider
        }
        return provider == .cloud ? "Cloud" : "Local"
    }

    var sourceLabel: String {
        mode.isMeeting ? "System + microphone" : "Microphone"
    }

    var targetLabel: String? {
        switch mode {
        case let .translation(targetLanguage):
            targetLanguage
        case .meetingTranslation:
            SettingsStorage.shared.resolveTranslationLanguagePair().displayLabel
        case .voice, .meeting, .fileTranscription:
            nil
        }
    }

    func reset(mode: RecordingMode) {
        self.mode = mode
        phase = .starting
        connectionStatus = .disconnected
        audioLevel = 0
        startedAt = Date()
        finalText = ""
        provisionalText = ""
        fallbackFinalText = ""
        fallbackProvisionalText = ""
        meetingTranscript.reset()
        copiedAt = nil
    }

    func processTokens(_ tokens: [RealtimeToken]) {
        if mode == .meeting {
            meetingTranscript.processTokens(tokens)
        }

        let isTranslationMode: Bool = {
            switch mode {
            case .translation, .meetingTranslation:
                true
            case .voice, .meeting, .fileTranscription:
                false
            }
        }()

        var provisionalPrimary = ""
        var provisionalFallback = ""

        for token in tokens where !token.text.isEmpty {
            if token.isFinal {
                if isTranslationMode {
                    if token.isTranslationOutput {
                        finalText += token.text
                    } else {
                        fallbackFinalText += token.text
                    }
                } else {
                    finalText += token.text
                }
                continue
            }

            if isTranslationMode {
                if token.isTranslationOutput {
                    provisionalPrimary += token.text
                } else {
                    provisionalFallback += token.text
                }
            } else {
                provisionalPrimary += token.text
            }
        }

        if !provisionalPrimary.isEmpty || !provisionalFallback.isEmpty {
            provisionalText = provisionalPrimary
            fallbackProvisionalText = provisionalFallback
        } else if tokens.contains(where: { $0.isFinal }) {
            provisionalText = ""
            fallbackProvisionalText = ""
        }
    }

    func markSegmentBoundary() {
        guard mode == .meeting else { return }
        meetingTranscript.markSegmentBoundary()
    }

    func bestText(includeProvisional: Bool) -> String {
        let primary = composedText(final: finalText, provisional: includeProvisional ? provisionalText : "")
        if !primary.isEmpty {
            return primary
        }

        return composedText(
            final: fallbackFinalText,
            provisional: includeProvisional ? fallbackProvisionalText : ""
        )
    }

    func markCopied() {
        copiedAt = Date()
    }

    private func composedText(final: String, provisional: String) -> String {
        (final + provisional).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension RealtimeToken {
    var isTranslationOutput: Bool {
        switch translationStatus?.lowercased() {
        case "translation", "translated", "target":
            true
        default:
            false
        }
    }
}
