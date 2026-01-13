import AppKit
import Foundation

// MARK: - Meeting Recording

extension AppDelegate {
    @objc func toggleMeetingRecording() {
        Log.app.info("toggleMeetingRecording called, current state: \(self.appState.meetingRecordingState)")
        Task {
            await self.performToggleMeetingRecording()
        }
    }

    func performToggleMeetingRecording() async {
        switch appState.meetingRecordingState {
        case .idle:
            await startMeetingRecording()
        case .recording:
            await stopMeetingRecording()
        default:
            Log.app.info("Meeting state is \(self.appState.meetingRecordingState), ignoring toggle")
        }
    }

    func startMeetingRecording() async {
        Log.app.info("startMeetingRecording: BEGIN")

        guard #available(macOS 13.0, *) else {
            Log.app.info("Meeting recording requires macOS 13.0+")
            await MainActor.run {
                appState.errorMessage = "Meeting recording requires macOS 13.0 or later"
                appState.meetingRecordingState = .error
            }
            return
        }

        // Request screen capture permission on-demand
        let hasPermission = await PermissionManager.shared.ensureScreenRecordingPermission()
        appState.screenCapturePermissionGranted = hasPermission

        guard hasPermission else {
            Log.app.info("Screen capture permission not granted")
            await MainActor.run {
                appState.errorMessage = "Screen recording permission required for meeting capture"
                appState.meetingRecordingState = .error
            }
            return
        }

        guard let apiKey = KeychainManager.shared.getSonioxAPIKey(), !apiKey.isEmpty else {
            Log.app.info("No API key for meeting recording")
            await MainActor.run {
                appState.errorMessage = "Please add your Soniox API key in Settings"
                appState.meetingRecordingState = .error
            }
            return
        }

        await MainActor.run {
            appState.meetingRecordingState = .recording
            appState.meetingRecordingStartTime = Date()
        }

        do {
            meetingRecorderService.audioSource = SettingsStorage.shared.meetingAudioSource
            try await meetingRecorderService.startRecording()
            Log.app.info("Meeting recording started")
        } catch {
            Log.app.info("Meeting recording failed: \(error)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.meetingRecordingState = .error
            }
        }
    }

    func stopMeetingRecording() async {
        Log.app.info("stopMeetingRecording: BEGIN")

        guard #available(macOS 13.0, *) else { return }

        await MainActor.run {
            appState.meetingRecordingState = .processing
        }

        do {
            guard let audioURL = try await meetingRecorderService.stopRecording() else {
                throw MeetingRecorderError.recordingFailed
            }

            let audioData = try Data(contentsOf: audioURL)
            Log.app.info("Meeting recording stopped, size = \(audioData.count) bytes")

            guard let apiKey = KeychainManager.shared.getSonioxAPIKey() else {
                throw TranscriptionError.noAPIKey
            }

            Log.app.info("Transcribing meeting recording...")
            transcriptionService.apiKey = apiKey
            let text = try await transcriptionService.transcribe(audioData: audioData)
            Log.app.info("Meeting transcription received: \(text.prefix(100))...")

            clipboardService.copy(text: text)
            Log.app.info("stopMeetingRecording: Text copied to clipboard")

            if SettingsStorage.shared.autoPaste {
                Log.app.info("stopMeetingRecording: Auto-pasting")
                do {
                    try await clipboardService.paste()
                } catch ClipboardError.accessibilityNotGranted {
                    Log.app.info("stopMeetingRecording: Accessibility permission needed")
                    PermissionManager.shared.showPermissionAlert(for: .accessibility)
                } catch {
                    Log.app.info("stopMeetingRecording: Paste failed - \(error.localizedDescription)")
                }
            }

            if SettingsStorage.shared.playSoundOnCompletion {
                NSSound(named: .init("Funk"))?.play()
            }

            if SettingsStorage.shared.showNotification {
                NotificationManager.shared.showSuccess(text: "Meeting transcribed: \(text.prefix(100))...")
            }

            await MainActor.run {
                appState.lastTranscription = text
                appState.meetingRecordingState = .success
                appState.meetingRecordingStartTime = nil
            }

            // Clean up temp file
            try? FileManager.default.removeItem(at: audioURL)

        } catch {
            Log.app.info("Meeting transcription failed: \(error)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.meetingRecordingState = .error
                appState.meetingRecordingStartTime = nil
            }
        }

        Log.app.info("stopMeetingRecording: END")
    }
}
