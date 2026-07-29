import Testing

@testable import Diduny

@Suite("Recording feedback controls")
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
}
