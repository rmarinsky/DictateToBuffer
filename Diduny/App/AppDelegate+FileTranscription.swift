import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

// MARK: - File Transcription

extension AppDelegate {
    func transcribeFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Audio or Video File to Transcribe"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .audio,
            .mpeg4Audio,
            .mp3,
            .wav,
            .aiff,
            UTType("org.xiph.flac") ?? .audio,
            UTType("public.ogg-audio") ?? .audio,
            .mpeg4Movie,
            .movie,
            .video
        ]

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        Task {
            await processFileTranscription(fileURL: fileURL)
        }
    }

    private func processFileTranscription(fileURL: URL) async {
        Log.app.info("transcribeFile: BEGIN - \(fileURL.lastPathComponent)")
        let activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Transcribing imported media"
        )
        defer { ProcessInfo.processInfo.endActivity(activityToken) }

        await MainActor.run {
            appState.recordingState = .processing
            NotchManager.shared.startProcessing(mode: .fileTranscription)
        }

        do {
            NotchManager.shared.showInfo(message: "Preparing audio...", duration: 30)
            let preparedAudio = try await ImportedMediaAudioPreparer().prepare(sourceURL: fileURL)
            defer { preparedAudio.removeTemporaryFile() }
            let fileSize = try? preparedAudio.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            Log.app.info(
                "transcribeFile: Prepared audio-only file (\(fileSize ?? 0) bytes)"
            )

            let text: String
            if SettingsStorage.shared.effectiveTranscriptionProvider == .cloud {
                let asyncJobService = AsyncTranscriptionJobService()
                let hints = SettingsStorage.shared.speechLanguageHints
                var config: [String: Any] = ["mode": "transcribe"]
                if !hints.isEmpty {
                    config["language_hints"] = hints
                    config["language_hints_strict"] = true
                }

                text = try await asyncJobService.transcribeFileWithRetry(
                    audioFileURL: preparedAudio.fileURL,
                    config: config
                ) { status in
                    Task { @MainActor in
                        switch status {
                        case .queued:
                            NotchManager.shared.showInfo(message: "Queued...", duration: 30)
                        case .uploading:
                            NotchManager.shared.showInfo(message: "Uploading...", duration: 30)
                        case .processing:
                            NotchManager.shared.startProcessing(mode: .fileTranscription)
                        case .finalizing:
                            NotchManager.shared.showInfo(message: "Finishing up...", duration: 30)
                        default:
                            break
                        }
                    }
                }
            } else {
                let service = activeTranscriptionService
                let audioData = try await loadAudioData(from: preparedAudio.fileURL)
                text = try await service.transcribe(audioData: audioData)
            }
            Log.app.info("transcribeFile: Transcription received (\(text.count) chars)")

            clipboardService.copy(text: text)

            if SettingsStorage.shared.autoPaste {
                do {
                    try await clipboardService.paste()
                } catch ClipboardError.accessibilityNotGranted {
                    PermissionManager.shared.showPermissionAlert(for: .accessibility)
                } catch {
                    Log.app.error("transcribeFile: Paste failed - \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                appState.lastTranscription = text
                appState.isEmptyTranscription = false
                appState.recordingState = .success
                appState.recordingStartTime = nil
                if let text = appState.lastTranscription {
                    NotchManager.shared.showSuccess(text: text)
                }
            }

            // Auto-reset to idle
            voiceAutoResetTask?.cancel()
            voiceAutoResetTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                if appState.recordingState == .success {
                    appState.recordingState = .idle
                }
            }

            // Save only the derived audio file; the source video never enters the library.
            RecordingsLibraryStorage.shared.saveRecording(
                audioURL: preparedAudio.fileURL,
                type: .fileTranscription,
                duration: preparedAudio.durationSeconds,
                transcriptionText: text
            )

            if SettingsStorage.shared.playSoundOnCompletion {
                NSSound(named: .init("Funk"))?.play()
            }

        } catch is CancellationError {
            Log.app.info("transcribeFile: Cancelled")
            await MainActor.run {
                appState.recordingState = .idle
                appState.recordingStartTime = nil
                NotchManager.shared.hide()
            }
            return
        } catch {
            Log.app.error("transcribeFile: ERROR - \(error.localizedDescription)")

            let isEmptyTranscription: Bool = {
                guard case .emptyTranscription = error as? TranscriptionError else { return false }
                return true
            }()

            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.isEmptyTranscription = isEmptyTranscription
                appState.recordingState = .error
                NotchManager.shared.showError(message: error.localizedDescription)
            }

            // Auto-reset error to idle
            voiceAutoResetTask?.cancel()
            voiceAutoResetTask = Task {
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { return }
                if appState.recordingState == .error {
                    appState.recordingState = .idle
                }
            }
        }

        Log.app.info("transcribeFile: END")
    }
}
