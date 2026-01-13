import AppKit
import Foundation

// MARK: - Translation Recording (EN <-> UK)

extension AppDelegate {
    @objc func toggleTranslationRecording() {
        Log.app.info("toggleTranslationRecording called, current state: \(self.appState.translationRecordingState)")
        Task {
            await self.performToggleTranslationRecording()
        }
    }

    func performToggleTranslationRecording() async {
        switch appState.translationRecordingState {
        case .idle:
            await startTranslationRecording()
        case .recording:
            await stopTranslationRecording()
        default:
            Log.app.info("Translation state is \(self.appState.translationRecordingState), ignoring toggle")
        }
    }

    func startTranslationRecordingIfIdle() async {
        guard appState.translationRecordingState == .idle else {
            Log.app.info("startTranslationRecordingIfIdle: Not idle, ignoring")
            return
        }
        await startTranslationRecording()
    }

    func stopTranslationRecordingIfRecording() async {
        guard appState.translationRecordingState == .recording else {
            Log.app.info("stopTranslationRecordingIfRecording: Not recording, ignoring")
            return
        }
        await stopTranslationRecording()
    }

    func startTranslationRecording() async {
        Log.app.info("startTranslationRecording: BEGIN")

        // Request microphone permission on-demand
        let micGranted = await PermissionManager.shared.ensureMicrophonePermission()
        appState.microphonePermissionGranted = micGranted

        guard micGranted else {
            Log.app.info("startTranslationRecording: Microphone permission not granted")
            await MainActor.run {
                appState.errorMessage = "Microphone access required"
                appState.translationRecordingState = .error
            }
            return
        }

        guard let apiKey = KeychainManager.shared.getSonioxAPIKey(), !apiKey.isEmpty else {
            Log.app.info("startTranslationRecording: No API key found")
            await MainActor.run {
                appState.errorMessage = "Please add your Soniox API key in Settings"
                appState.translationRecordingState = .error
            }
            return
        }
        Log.app.info("startTranslationRecording: API key found")

        // Determine device
        var device: AudioDevice?
        if appState.useAutoDetect {
            Log.app.info("startTranslationRecording: Using auto-detect")
            await MainActor.run { appState.translationRecordingState = .processing }
            device = await audioDeviceManager.autoDetectBestDevice()
            Log.app.info("startTranslationRecording: Auto-detected device: \(device?.name ?? "none")")
        } else if let deviceID = appState.selectedDeviceID {
            device = audioDeviceManager.availableDevices.first { $0.id == deviceID }
            Log.app.info("startTranslationRecording: Using selected device: \(device?.name ?? "none")")
        }

        Log.app.info("startTranslationRecording: Setting state to recording")
        await MainActor.run {
            appState.translationRecordingState = .recording
            appState.translationRecordingStartTime = Date()
        }

        do {
            Log.app.info("startTranslationRecording: Starting audio recording")
            try await audioRecorder.startRecording(
                device: device,
                quality: SettingsStorage.shared.audioQuality
            )
            Log.app.info("startTranslationRecording: Recording started successfully")
        } catch {
            Log.app.info("startTranslationRecording: ERROR - \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.translationRecordingState = .error
            }
        }
    }

    func stopTranslationRecording() async {
        Log.app.info("stopTranslationRecording: BEGIN")

        await MainActor.run {
            appState.translationRecordingState = .processing
        }

        do {
            Log.app.info("stopTranslationRecording: Stopping audio recorder")
            let audioData = try await audioRecorder.stopRecording()
            Log.app.info("stopTranslationRecording: Got audio data, size = \(audioData.count) bytes")

            guard let apiKey = KeychainManager.shared.getSonioxAPIKey() else {
                Log.app.info("stopTranslationRecording: No API key!")
                throw TranscriptionError.noAPIKey
            }

            Log.app.info("stopTranslationRecording: Calling translation service (EN <-> UK)")
            transcriptionService.apiKey = apiKey
            let text = try await transcriptionService.translateAndTranscribe(audioData: audioData)
            Log.app.info("stopTranslationRecording: Translation received: \(text.prefix(50))...")

            clipboardService.copy(text: text)
            Log.app.info("stopTranslationRecording: Text copied to clipboard")

            if SettingsStorage.shared.autoPaste {
                Log.app.info("stopTranslationRecording: Auto-pasting")
                do {
                    try await clipboardService.paste()
                } catch ClipboardError.accessibilityNotGranted {
                    Log.app.info("stopTranslationRecording: Accessibility permission needed")
                    PermissionManager.shared.showPermissionAlert(for: .accessibility)
                } catch {
                    Log.app.info("stopTranslationRecording: Paste failed - \(error.localizedDescription)")
                }
            }

            if SettingsStorage.shared.playSoundOnCompletion {
                Log.app.info("stopTranslationRecording: Playing sound")
                NSSound(named: .init("Funk"))?.play()
            }

            if SettingsStorage.shared.showNotification {
                Log.app.info("stopTranslationRecording: Showing notification")
                NotificationManager.shared.showSuccess(text: "Translated: \(text.prefix(50))...")
            }

            await MainActor.run {
                appState.lastTranscription = text
                appState.translationRecordingState = .success
                appState.translationRecordingStartTime = nil
            }
            Log.app.info("stopTranslationRecording: SUCCESS")

        } catch {
            Log.app.info("stopTranslationRecording: ERROR - \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.translationRecordingState = .error
                appState.translationRecordingStartTime = nil
            }
        }
        Log.app.info("stopTranslationRecording: END")
    }
}
