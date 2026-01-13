import AppKit
import AVFoundation
import Combine
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    var recordingWindow: NSWindow?

    let appState = AppState()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Services (exposed for SwiftUI access)

    lazy var audioDeviceManager = AudioDeviceManager()
    lazy var audioRecorder = AudioRecorderService()
    lazy var transcriptionService = SonioxTranscriptionService()
    lazy var clipboardService = ClipboardService()
    lazy var hotkeyService = HotkeyService()
    lazy var pushToTalkService = PushToTalkService()
    lazy var meetingHotkeyService = HotkeyService()
    lazy var translationHotkeyService = HotkeyService()
    lazy var translationPushToTalkService = PushToTalkService()
    @available(macOS 13.0, *)
    lazy var meetingRecorderService = MeetingRecorderService()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        setupBindings()

        // Listen for push-to-talk key changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pushToTalkKeyChanged(_:)),
            name: .pushToTalkKeyChanged,
            object: nil
        )

        // Listen for hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyChanged(_:)),
            name: .hotkeyChanged,
            object: nil
        )

        // Listen for translation hotkey changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(translationHotkeyChanged(_:)),
            name: .translationHotkeyChanged,
            object: nil
        )

        // Listen for translation push-to-talk key changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(translationPushToTalkKeyChanged(_:)),
            name: .translationPushToTalkKeyChanged,
            object: nil
        )

        // Setup hotkey and push-to-talk immediately
        // Permissions will be requested on-demand when user tries to record
        setupHotkey()
        setupPushToTalk()
        setupTranslationHotkey()
        setupTranslationPushToTalk()

        // Check for API key
        if KeychainManager.shared.getSonioxAPIKey() == nil {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                openSettings()
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        hotkeyService.unregister()
        pushToTalkService.stop()
        translationHotkeyService.unregister()
        translationPushToTalkService.stop()
    }

    // MARK: - Bindings

    private func setupBindings() {
        appState.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateRecordingWindow(for: state)
                self?.handleRecordingStateChange(state)
            }
            .store(in: &cancellables)

        appState.$meetingRecordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleMeetingStateChange(state)
            }
            .store(in: &cancellables)

        appState.$translationRecordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateRecordingWindowForTranslation(for: state)
                self?.handleTranslationStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func handleRecordingStateChange(_ state: RecordingState) {
        switch state {
        case .success:
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if self.appState.recordingState == .success {
                    self.appState.recordingState = .idle
                }
            }
        case .error:
            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.appState.recordingState == .error {
                    self.appState.recordingState = .idle
                }
            }
        default:
            break
        }
    }

    private func handleMeetingStateChange(_ state: MeetingRecordingState) {
        switch state {
        case .success:
            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.appState.meetingRecordingState == .success {
                    self.appState.meetingRecordingState = .idle
                }
            }
        case .error:
            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.appState.meetingRecordingState == .error {
                    self.appState.meetingRecordingState = .idle
                }
            }
        default:
            break
        }
    }

    private func handleTranslationStateChange(_ state: TranslationRecordingState) {
        switch state {
        case .success:
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if self.appState.translationRecordingState == .success {
                    self.appState.translationRecordingState = .idle
                }
            }
        case .error:
            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.appState.translationRecordingState == .error {
                    self.appState.translationRecordingState = .idle
                }
            }
        default:
            break
        }
    }

    // MARK: - Device Selection (exposed for SwiftUI)

    func selectAutoDetect() {
        appState.useAutoDetect = true
        appState.selectedDeviceID = nil
    }

    func selectDevice(_ device: AudioDevice) {
        appState.useAutoDetect = false
        appState.selectedDeviceID = device.id
    }

    // MARK: - Settings

    func openSettings() {
        // Trigger settings opening via AppState (observed by SwiftUI)
        appState.shouldOpenSettings = true
    }
}
