@testable import Diduny
import Testing

@MainActor
struct RecordingFeedbackControllerTests {
    @Test("Stop cancels voice recording while it is still starting")
    func stopCancelsStartingVoiceRecording() async {
        let delegate = AppDelegate()
        delegate.appState.recordingState = .processing

        await delegate.stopActiveRecordingFromFeedback()

        #expect(delegate.appState.recordingState == .idle)
    }

    @Test("Stop does not cancel voice recording while it is finalizing")
    func stopDoesNotCancelFinalizingVoiceRecording() async {
        let delegate = AppDelegate()
        delegate.appState.recordingState = .processing
        delegate.appState.recordingStartTime = Date()

        await delegate.stopActiveRecordingFromFeedback()

        #expect(delegate.appState.recordingState == .processing)
    }

    @Test("Dynamic Notch surface never feeds the live transcript")
    func notchSurfaceSkipsLiveTranscriptTokens() {
        let previousSurface = SettingsStorage.shared.recordingFeedbackSurface
        defer {
            SettingsStorage.shared.recordingFeedbackSurface = previousSurface
            DictationOverlayController.shared.dismiss()
        }
        let sut = DictationOverlayController.shared

        SettingsStorage.shared.recordingFeedbackSurface = .notch
        sut.begin(mode: .voice)
        sut.processTokens([RealtimeToken(text: "hidden", isFinal: true)])
        #expect(!sut.store.displayText.contains("hidden"))
        sut.dismiss()

        SettingsStorage.shared.recordingFeedbackSurface = .compactPanel
        sut.begin(mode: .voice)
        sut.processTokens([RealtimeToken(text: "visible", isFinal: true)])
        #expect(sut.store.displayText.contains("visible"))
    }

    @Test("A mid-recording surface flip keeps the session on its starting surface")
    func surfaceFlipMidRecordingDoesNotRerouteSession() {
        let previousSurface = SettingsStorage.shared.recordingFeedbackSurface
        defer {
            SettingsStorage.shared.recordingFeedbackSurface = previousSurface
            DictationOverlayController.shared.dismiss()
        }
        let sut = DictationOverlayController.shared

        SettingsStorage.shared.recordingFeedbackSurface = .compactPanel
        sut.begin(mode: .voice)
        SettingsStorage.shared.recordingFeedbackSurface = .notch
        sut.processTokens([RealtimeToken(text: "still panel", isFinal: true)])
        #expect(sut.store.displayText.contains("still panel"))
        sut.dismiss()

        // Next session picks up the flipped setting.
        sut.begin(mode: .voice)
        sut.processTokens([RealtimeToken(text: "now notch", isFinal: true)])
        #expect(!sut.store.displayText.contains("now notch"))
    }
}
