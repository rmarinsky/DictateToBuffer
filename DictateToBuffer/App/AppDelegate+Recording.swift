import AppKit
import Foundation

// MARK: - Recording Actions

extension AppDelegate {
    @objc func toggleRecording() {
        Log.app.info("toggleRecording called, current state: \(self.appState.recordingState)")
        Task {
            await self.performToggleRecording()
        }
    }

    func performToggleRecording() async {
        Log.app.info("performToggleRecording: state = \(self.appState.recordingState)")
        switch appState.recordingState {
        case .idle:
            Log.app.info("State is idle, starting recording...")
            await startRecording()
        case .recording:
            Log.app.info("State is recording, stopping recording...")
            await stopRecording()
        default:
            Log.app.info("State is \(self.appState.recordingState), ignoring toggle")
        }
    }

    func startRecordingIfIdle() async {
        guard appState.recordingState == .idle else {
            Log.app.info("startRecordingIfIdle: Not idle, ignoring")
            return
        }
        await startRecording()
    }

    func stopRecordingIfRecording() async {
        guard appState.recordingState == .recording else {
            Log.app.info("stopRecordingIfRecording: Not recording, ignoring")
            return
        }
        await stopRecording()
    }

    func startRecording() async {
        Log.app.info("startRecording: BEGIN")

        // Request microphone permission on-demand
        let micGranted = await PermissionManager.shared.ensureMicrophonePermission()
        appState.microphonePermissionGranted = micGranted

        guard micGranted else {
            Log.app.info("startRecording: Microphone permission not granted")
            await MainActor.run {
                appState.errorMessage = "Microphone access required"
                appState.recordingState = .error
            }
            return
        }

        guard let apiKey = KeychainManager.shared.getSonioxAPIKey(), !apiKey.isEmpty else {
            Log.app.info("startRecording: No API key found")
            await MainActor.run {
                appState.errorMessage = "Please add your Soniox API key in Settings"
                appState.recordingState = .error
            }
            return
        }
        Log.app.info("startRecording: API key found")

        // Determine device
        var device: AudioDevice?
        if appState.useAutoDetect {
            Log.app.info("startRecording: Using auto-detect")
            await MainActor.run { appState.recordingState = .processing }
            device = await audioDeviceManager.autoDetectBestDevice()
            Log.app.info("startRecording: Auto-detected device: \(device?.name ?? "none")")
        } else if let deviceID = appState.selectedDeviceID {
            device = audioDeviceManager.availableDevices.first { $0.id == deviceID }
            Log.app.info("startRecording: Using selected device: \(device?.name ?? "none")")
        }

        Log.app.info("startRecording: Setting state to recording")
        await MainActor.run {
            appState.recordingState = .recording
            appState.recordingStartTime = Date()
        }

        do {
            Log.app.info("startRecording: Starting audio recording")
            try await audioRecorder.startRecording(
                device: device,
                quality: SettingsStorage.shared.audioQuality
            )
            Log.app.info("startRecording: Recording started successfully")
        } catch {
            Log.app.info("startRecording: ERROR - \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.recordingState = .error
            }
        }
    }

    func stopRecording() async {
        Log.app.info("stopRecording: BEGIN")

        await MainActor.run {
            appState.recordingState = .processing
        }

        do {
            Log.app.info("stopRecording: Stopping audio recorder")
            let audioData = try await audioRecorder.stopRecording()
            Log.app.info("stopRecording: Got audio data, size = \(audioData.count) bytes")

            guard let apiKey = KeychainManager.shared.getSonioxAPIKey() else {
                Log.app.info("stopRecording: No API key!")
                throw TranscriptionError.noAPIKey
            }

            Log.app.info("stopRecording: Calling transcription service")
            transcriptionService.apiKey = apiKey
            let text = try await transcriptionService.transcribe(audioData: audioData)
            Log.app.info("stopRecording: Transcription received: \(text.prefix(50))...")

            clipboardService.copy(text: text)
            Log.app.info("stopRecording: Text copied to clipboard")

            if SettingsStorage.shared.autoPaste {
                Log.app.info("stopRecording: Auto-pasting")
                do {
                    try await clipboardService.paste()
                } catch ClipboardError.accessibilityNotGranted {
                    Log.app.info("stopRecording: Accessibility permission needed")
                    PermissionManager.shared.showPermissionAlert(for: .accessibility)
                } catch {
                    Log.app.info("stopRecording: Paste failed - \(error.localizedDescription)")
                }
            }

            if SettingsStorage.shared.playSoundOnCompletion {
                Log.app.info("stopRecording: Playing sound")
                NSSound(named: .init("Funk"))?.play()
            }

            if SettingsStorage.shared.showNotification {
                Log.app.info("stopRecording: Showing notification")
                NotificationManager.shared.showSuccess(text: "Transcribed: \(text.prefix(50))...")
            }

            await MainActor.run {
                appState.lastTranscription = text
                appState.recordingState = .success
                appState.recordingStartTime = nil
            }
            Log.app.info("stopRecording: SUCCESS")

        } catch {
            Log.app.info("stopRecording: ERROR - \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.recordingState = .error
                appState.recordingStartTime = nil
            }
        }
        Log.app.info("stopRecording: END")
    }
}
