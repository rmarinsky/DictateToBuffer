import Foundation

@MainActor
final class DictationOverlayController {
    static let shared = DictationOverlayController()

    let store = LiveDictationOverlayStore()
    private var autoHideTask: Task<Void, Never>?
    private var onStopRequested: (@MainActor () async -> Void)?

    private init() {}

    func setStopHandler(_ handler: (@MainActor () async -> Void)?) {
        onStopRequested = handler
    }

    func begin(mode: RecordingMode) {
        autoHideTask?.cancel()
        store.reset(mode: mode)
        store.phase = .starting
        showPanel()
    }

    func startRecording(mode: RecordingMode) {
        autoHideTask?.cancel()
        if store.mode != mode {
            store.reset(mode: mode)
        }
        store.phase = .recording
        showPanel()
    }

    func startFinalizing(mode: RecordingMode) {
        autoHideTask?.cancel()
        if store.mode != mode {
            store.mode = mode
        }
        store.phase = .finalizing
        store.audioLevel = 0
        showPanel()
    }

    func startProcessing(mode: RecordingMode) {
        autoHideTask?.cancel()
        if store.mode != mode {
            store.mode = mode
        }
        store.phase = .processing
        store.audioLevel = 0
        showPanel()
    }

    func showSuccess(text: String) {
        autoHideTask?.cancel()
        if !text.isEmpty {
            store.finalText = text
            store.provisionalText = ""
        }
        store.phase = .pasted
        store.audioLevel = 0
        showPanel()
        if SettingsStorage.shared.autoPaste {
            scheduleAutoHide(delay: 0.8)
        }
    }

    func showError(message: String) {
        autoHideTask?.cancel()
        store.phase = .error(message)
        store.audioLevel = 0
        showPanel()
        scheduleAutoHide(delay: 3.0)
    }

    func showInfo(message: String, duration: TimeInterval = 1.5) {
        autoHideTask?.cancel()
        store.phase = .info(message)
        store.audioLevel = 0
        showPanel()
        scheduleAutoHide(delay: duration)
    }

    func showInfoDuringRecording(message: String, mode: RecordingMode, duration: TimeInterval = 1.5) {
        autoHideTask?.cancel()
        let savedPhase = store.phase
        let savedStart = store.startedAt
        store.mode = mode
        store.phase = .info(message)
        showPanel()
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.store.startedAt = savedStart
                self.store.phase = savedPhase
                self.showPanel()
            }
        }
    }

    func hide() {
        guard store.phase != .pasted || SettingsStorage.shared.autoPaste else { return }
        dismiss()
    }

    func dismiss() {
        autoHideTask?.cancel()
        autoHideTask = nil
        store.audioLevel = 0
        EdgeCommandPanelController.shared.dismissLiveFeedback()
    }

    func updateAudioLevel(_ level: Float) {
        store.audioLevel = max(0, min(level, 1))
    }

    func processTokens(_ tokens: [RealtimeToken]) {
        guard !tokens.isEmpty else { return }
        store.processTokens(tokens)
    }

    func updateConnectionStatus(_ status: RealtimeConnectionStatus) {
        store.connectionStatus = status
    }

    func copyCurrentTranscript() {
        let text = store.displayText
        guard !text.isEmpty else { return }
        ClipboardService.shared.copy(text: text, behavior: .raw)
        store.markCopied()
    }

    func requestStop() {
        guard let onStopRequested else { return }
        Task { @MainActor in
            await onStopRequested()
        }
    }

    private func showPanel() {
        EdgeCommandPanelController.shared.showLiveFeedback(mode: store.mode)
    }

    private func scheduleAutoHide(delay: TimeInterval) {
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.hide()
            }
        }
    }
}
