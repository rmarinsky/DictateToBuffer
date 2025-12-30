import AppKit
import SwiftUI
import Combine
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var popover: NSPopover?
    private var recordingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    let appState = AppState()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Services

    private lazy var audioDeviceManager = AudioDeviceManager()
    private lazy var audioRecorder = AudioRecorderService()
    private lazy var transcriptionService = SonioxTranscriptionService()
    private lazy var clipboardService = ClipboardService()
    private lazy var hotkeyService = HotkeyService()
    private lazy var pushToTalkService = PushToTalkService()
    private lazy var meetingHotkeyService = HotkeyService()
    @available(macOS 13.0, *)
    private lazy var meetingRecorderService = MeetingRecorderService()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
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

        // Request all permissions at startup
        requestAllPermissions()
    }

    // MARK: - Permissions

    private func requestAllPermissions() {
        NSLog("[DictateToBuffer] Requesting all permissions at startup...")
        
        PermissionManager.shared.requestAllPermissions { [weak self] status in
            guard let self = self else { return }
            
            NSLog("[DictateToBuffer] Permissions granted: Mic=\(status.microphone), Accessibility=\(status.accessibility), Screen=\(status.screenRecording), Notifications=\(status.notifications)")
            
            // Update app state
            self.appState.microphonePermissionGranted = status.microphone
            
            // Setup features that require permissions
            if status.microphone {
                self.setupHotkey()
                self.setupPushToTalk()
            }
            
            // Check for API key after permissions
            if KeychainManager.shared.getSonioxAPIKey() == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.openSettings()
                }
            }
        }
    }

    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            NSLog("[DictateToBuffer] Microphone permission already granted")
            onMicrophonePermissionGranted()

        case .notDetermined:
            NSLog("[DictateToBuffer] Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        NSLog("[DictateToBuffer] Microphone permission granted")
                        self?.onMicrophonePermissionGranted()
                    } else {
                        NSLog("[DictateToBuffer] Microphone permission denied")
                        self?.onMicrophonePermissionDenied()
                    }
                }
            }

        case .denied, .restricted:
            NSLog("[DictateToBuffer] Microphone permission denied/restricted")
            onMicrophonePermissionDenied()

        @unknown default:
            NSLog("[DictateToBuffer] Unknown microphone permission status")
            onMicrophonePermissionDenied()
        }
    }

    private func onMicrophonePermissionGranted() {
        appState.microphonePermissionGranted = true

        // Now safe to setup recording features
        setupHotkey()
        setupPushToTalk()

        // Check for API key
        if KeychainManager.shared.getSonioxAPIKey() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openSettings()
            }
        }
    }

    private func onMicrophonePermissionDenied() {
        appState.microphonePermissionGranted = false
        appState.errorMessage = "Microphone access required. Please enable in System Settings > Privacy & Security > Microphone"

        // Show alert
        let alert = NSAlert()
        alert.messageText = "Microphone Access Required"
        alert.informativeText = "DictateToBuffer needs microphone access to record audio for transcription.\n\nPlease enable it in System Settings > Privacy & Security > Microphone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.unregister()
        pushToTalkService.stop()
    }

    // MARK: - Status Bar Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "🥒"
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Recording toggle
        let recordItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(toggleRecording),
            keyEquivalent: "d"
        )
        recordItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(recordItem)

        // Meeting recording toggle
        let meetingTitle = appState.meetingRecordingState == .recording ? "Stop Meeting Recording" : "Record Meeting"
        let meetingItem = NSMenuItem(
            title: meetingTitle,
            action: #selector(toggleMeetingRecording),
            keyEquivalent: "m"
        )
        meetingItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(meetingItem)

        menu.addItem(NSMenuItem.separator())

        // Audio device submenu
        let deviceMenu = NSMenu()
        let deviceItem = NSMenuItem(title: "Audio Device", action: nil, keyEquivalent: "")
        deviceItem.submenu = deviceMenu
        menu.addItem(deviceItem)

        // Auto-detect option
        let autoItem = NSMenuItem(
            title: "Auto-detect",
            action: #selector(selectAutoDetect),
            keyEquivalent: ""
        )
        autoItem.state = appState.useAutoDetect ? .on : .off
        deviceMenu.addItem(autoItem)
        deviceMenu.addItem(NSMenuItem.separator())

        // Device list
        for device in audioDeviceManager.availableDevices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectDevice(_:)),
                keyEquivalent: ""
            )
            item.representedObject = device
            item.state = (appState.selectedDeviceID == device.id && !appState.useAutoDetect) ? .on : .off
            deviceMenu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        // Store menu separately - don't assign to statusItem to allow left-click action
        statusMenu = menu
    }

    // MARK: - Bindings

    private func setupBindings() {
        appState.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusIcon()
                self?.updateRecordingWindow(for: state)
            }
            .store(in: &cancellables)

        appState.$meetingRecordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusIcon()
                self?.handleMeetingStateChange(state)
            }
            .store(in: &cancellables)

        audioDeviceManager.$availableDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.setupMenu()
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        button.image = nil

        // Meeting recording takes priority in icon display
        if appState.meetingRecordingState == .recording {
            button.title = "🎙️"  // Meeting recording
            return
        }
        if appState.meetingRecordingState == .processing {
            button.title = "⏳"
            return
        }

        switch appState.recordingState {
        case .idle:
            if appState.meetingRecordingState == .success {
                button.title = "✅"
            } else if appState.meetingRecordingState == .error {
                button.title = "❌"
            } else {
                button.title = "🥒"
            }
        case .recording:
            button.title = "🔴"
        case .processing:
            button.title = "⏳"
        case .success:
            button.title = "✅"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.appState.recordingState == .success {
                    self.appState.recordingState = .idle
                }
            }
        case .error:
            button.title = "❌"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.appState.recordingState == .error {
                    self.appState.recordingState = .idle
                }
            }
        }
    }

    private func handleMeetingStateChange(_ state: MeetingRecordingState) {
        switch state {
        case .success:
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.appState.meetingRecordingState == .success {
                    self.appState.meetingRecordingState = .idle
                }
            }
        case .error:
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.appState.meetingRecordingState == .error {
                    self.appState.meetingRecordingState = .idle
                }
            }
        default:
            break
        }
    }

    // MARK: - Recording Window (Minimal Pill)

    private func updateRecordingWindow(for state: RecordingState) {
        switch state {
        case .recording, .processing:
            showRecordingWindow()
        case .success:
            updateRecordingWindowContent()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.hideRecordingWindow()
            }
        case .idle, .error:
            hideRecordingWindow()
        }
    }

    private func showRecordingWindow() {
        if recordingWindow == nil {
            let contentView = RecordingIndicatorView()
                .environmentObject(appState)

            let hostingView = NSHostingView(rootView: contentView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 150, height: 40)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 150, height: 40),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.isMovableByWindowBackground = true

            // Position top-right
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.maxX - 160
                let y = screenFrame.maxY - 54
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            recordingWindow = window
        }

        recordingWindow?.orderFront(nil)
    }

    private func updateRecordingWindowContent() {
        // Content updates via appState binding
    }

    private func hideRecordingWindow() {
        recordingWindow?.orderOut(nil)
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let settings = SettingsStorage.shared
        if let hotkey = settings.globalHotkey {
            try? hotkeyService.register(keyCombo: hotkey) { [weak self] in
                self?.toggleRecording()
            }
        }
    }

    // MARK: - Push to Talk

    private func setupPushToTalk() {
        let key = SettingsStorage.shared.pushToTalkKey
        pushToTalkService.selectedKey = key

        pushToTalkService.onKeyDown = { [weak self] in
            guard let self = self else { return }
            Task {
                await self.startRecordingIfIdle()
            }
        }

        pushToTalkService.onKeyUp = { [weak self] in
            guard let self = self else { return }
            Task {
                await self.stopRecordingIfRecording()
            }
        }

        if key != .none {
            pushToTalkService.start()
        }
    }

    @objc private func pushToTalkKeyChanged(_ notification: Notification) {
        guard let key = notification.object as? PushToTalkKey else { return }
        NSLog("[DictateToBuffer] Push-to-talk key changed to: \(key.displayName)")

        pushToTalkService.stop()
        pushToTalkService.selectedKey = key

        if key != .none {
            pushToTalkService.start()
        }
    }

    @objc private func hotkeyChanged(_ notification: Notification) {
        NSLog("[DictateToBuffer] Hotkey changed")

        // Unregister old hotkey
        hotkeyService.unregister()

        // Register new hotkey if set
        if let combo = notification.object as? KeyCombo {
            NSLog("[DictateToBuffer] Registering new hotkey: \(combo.displayString)")
            try? hotkeyService.register(keyCombo: combo) { [weak self] in
                self?.toggleRecording()
            }
        }
    }

    private func startRecordingIfIdle() async {
        guard appState.recordingState == .idle else {
            NSLog("[DictateToBuffer] startRecordingIfIdle: Not idle, ignoring")
            return
        }
        await startRecording()
    }

    private func stopRecordingIfRecording() async {
        guard appState.recordingState == .recording else {
            NSLog("[DictateToBuffer] stopRecordingIfRecording: Not recording, ignoring")
            return
        }
        await stopRecording()
    }

    // MARK: - Actions

    @objc private func statusItemClicked(_ sender: Any?) {
        statusMenu?.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: 0),
            in: statusItem?.button
        )
    }

    @objc private func toggleRecording() {
        NSLog("[DictateToBuffer] toggleRecording called, current state: \(appState.recordingState)")
        Task {
            await performToggleRecording()
        }
    }

    private func performToggleRecording() async {
        NSLog("[DictateToBuffer] performToggleRecording: state = \(appState.recordingState)")
        switch appState.recordingState {
        case .idle:
            NSLog("[DictateToBuffer] State is idle, starting recording...")
            await startRecording()
        case .recording:
            NSLog("[DictateToBuffer] State is recording, stopping recording...")
            await stopRecording()
        default:
            NSLog("[DictateToBuffer] State is \(appState.recordingState), ignoring toggle")
            break
        }
    }

    private func startRecording() async {
        NSLog("[DictateToBuffer] startRecording: BEGIN")

        // Check microphone permission first
        guard appState.microphonePermissionGranted else {
            NSLog("[DictateToBuffer] startRecording: Microphone permission not granted")
            await MainActor.run {
                appState.errorMessage = "Microphone access required"
                appState.recordingState = .error
            }
            PermissionManager.shared.showPermissionAlert(for: .microphone)
            return
        }

        guard let apiKey = KeychainManager.shared.getSonioxAPIKey(), !apiKey.isEmpty else {
            NSLog("[DictateToBuffer] startRecording: No API key found")
            await MainActor.run {
                appState.errorMessage = "Please add your Soniox API key in Settings"
                appState.recordingState = .error
            }
            return
        }
        NSLog("[DictateToBuffer] startRecording: API key found")

        // Determine device
        var device: AudioDevice?
        if appState.useAutoDetect {
            NSLog("[DictateToBuffer] startRecording: Using auto-detect, setting state to processing")
            await MainActor.run { appState.recordingState = .processing }
            device = await audioDeviceManager.autoDetectBestDevice()
            NSLog("[DictateToBuffer] startRecording: Auto-detected device: \(device?.name ?? "none")")
        } else if let deviceID = appState.selectedDeviceID {
            device = audioDeviceManager.availableDevices.first { $0.id == deviceID }
            NSLog("[DictateToBuffer] startRecording: Using selected device: \(device?.name ?? "none")")
        }

        NSLog("[DictateToBuffer] startRecording: Setting state to recording")
        await MainActor.run {
            appState.recordingState = .recording
            appState.recordingStartTime = Date()
        }
        NSLog("[DictateToBuffer] startRecording: State is now \(appState.recordingState)")

        do {
            NSLog("[DictateToBuffer] startRecording: Calling audioRecorder.startRecording()")
            try await audioRecorder.startRecording(
                device: device,
                quality: SettingsStorage.shared.audioQuality
            )
            NSLog("[DictateToBuffer] startRecording: Recording started successfully")
        } catch {
            NSLog("[DictateToBuffer] startRecording: ERROR - \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.recordingState = .error
            }
        }
        NSLog("[DictateToBuffer] startRecording: END, final state = \(appState.recordingState)")
    }

    private func stopRecording() async {
        NSLog("[DictateToBuffer] stopRecording: BEGIN")

        await MainActor.run {
            appState.recordingState = .processing
        }
        NSLog("[DictateToBuffer] stopRecording: State set to processing")

        do {
            NSLog("[DictateToBuffer] stopRecording: Calling audioRecorder.stopRecording()")
            let audioData = try await audioRecorder.stopRecording()
            NSLog("[DictateToBuffer] stopRecording: Got audio data, size = \(audioData.count) bytes")

            guard let apiKey = KeychainManager.shared.getSonioxAPIKey() else {
                NSLog("[DictateToBuffer] stopRecording: No API key!")
                throw TranscriptionError.noAPIKey
            }

            NSLog("[DictateToBuffer] stopRecording: Calling transcription service")
            transcriptionService.apiKey = apiKey
            let text = try await transcriptionService.transcribe(audioData: audioData)
            NSLog("[DictateToBuffer] stopRecording: Transcription received: \(text.prefix(50))...")

            clipboardService.copy(text: text)
            NSLog("[DictateToBuffer] stopRecording: Text copied to clipboard")

            if SettingsStorage.shared.autoPaste {
                NSLog("[DictateToBuffer] stopRecording: Auto-pasting")
                do {
                    try await clipboardService.paste()
                } catch ClipboardError.accessibilityNotGranted {
                    NSLog("[DictateToBuffer] stopRecording: Accessibility permission needed")
                    PermissionManager.shared.showPermissionAlert(for: .accessibility)
                } catch {
                    NSLog("[DictateToBuffer] stopRecording: Paste failed - \(error.localizedDescription)")
                }
            }

            if SettingsStorage.shared.playSoundOnCompletion {
                NSLog("[DictateToBuffer] stopRecording: Playing sound")
                NSSound(named: .init("Funk"))?.play()
            }

            if SettingsStorage.shared.showNotification {
                NSLog("[DictateToBuffer] stopRecording: Showing notification")
                NotificationManager.shared.showSuccess(text: text)
            }

            await MainActor.run {
                appState.lastTranscription = text
                appState.recordingState = .success
            }
            NSLog("[DictateToBuffer] stopRecording: SUCCESS")

        } catch {
            NSLog("[DictateToBuffer] stopRecording: ERROR - \(error.localizedDescription)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.recordingState = .error
            }
        }
        NSLog("[DictateToBuffer] stopRecording: END")
    }

    // MARK: - Meeting Recording

    @objc private func toggleMeetingRecording() {
        NSLog("[DictateToBuffer] toggleMeetingRecording called, current state: \(appState.meetingRecordingState)")
        Task {
            await performToggleMeetingRecording()
        }
    }

    private func performToggleMeetingRecording() async {
        switch appState.meetingRecordingState {
        case .idle:
            await startMeetingRecording()
        case .recording:
            await stopMeetingRecording()
        default:
            NSLog("[DictateToBuffer] Meeting state is \(appState.meetingRecordingState), ignoring toggle")
        }
    }

    private func startMeetingRecording() async {
        NSLog("[DictateToBuffer] startMeetingRecording: BEGIN")

        guard #available(macOS 13.0, *) else {
            NSLog("[DictateToBuffer] Meeting recording requires macOS 13.0+")
            await MainActor.run {
                appState.errorMessage = "Meeting recording requires macOS 13.0 or later"
                appState.meetingRecordingState = .error
            }
            return
        }

        // Check screen capture permission
        let hasPermission = await MeetingRecorderService.checkPermission()
        guard hasPermission else {
            NSLog("[DictateToBuffer] Screen capture permission not granted")
            await MainActor.run {
                appState.errorMessage = "Screen recording permission required for meeting capture"
                appState.meetingRecordingState = .error
            }
            PermissionManager.shared.showPermissionAlert(for: .screenRecording)
            return
        }

        guard let apiKey = KeychainManager.shared.getSonioxAPIKey(), !apiKey.isEmpty else {
            NSLog("[DictateToBuffer] No API key for meeting recording")
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
            NSLog("[DictateToBuffer] Meeting recording started")
            setupMenu() // Update menu title
        } catch {
            NSLog("[DictateToBuffer] Meeting recording failed: \(error)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.meetingRecordingState = .error
            }
        }
    }

    private func stopMeetingRecording() async {
        NSLog("[DictateToBuffer] stopMeetingRecording: BEGIN")

        guard #available(macOS 13.0, *) else { return }

        await MainActor.run {
            appState.meetingRecordingState = .processing
        }

        do {
            guard let audioURL = try await meetingRecorderService.stopRecording() else {
                throw MeetingRecorderError.recordingFailed
            }

            let audioData = try Data(contentsOf: audioURL)
            NSLog("[DictateToBuffer] Meeting recording stopped, size = \(audioData.count) bytes")

            guard let apiKey = KeychainManager.shared.getSonioxAPIKey() else {
                throw TranscriptionError.noAPIKey
            }

            NSLog("[DictateToBuffer] Transcribing meeting recording...")
            transcriptionService.apiKey = apiKey
            let text = try await transcriptionService.transcribe(audioData: audioData)
            NSLog("[DictateToBuffer] Meeting transcription received: \(text.prefix(100))...")

            clipboardService.copy(text: text)
            NSLog("[DictateToBuffer] stopMeetingRecording: Text copied to clipboard")

            if SettingsStorage.shared.autoPaste {
                NSLog("[DictateToBuffer] stopMeetingRecording: Auto-pasting")
                do {
                    try await clipboardService.paste()
                } catch ClipboardError.accessibilityNotGranted {
                    NSLog("[DictateToBuffer] stopMeetingRecording: Accessibility permission needed")
                    PermissionManager.shared.showPermissionAlert(for: .accessibility)
                } catch {
                    NSLog("[DictateToBuffer] stopMeetingRecording: Paste failed - \(error.localizedDescription)")
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
            NSLog("[DictateToBuffer] Meeting transcription failed: \(error)")
            await MainActor.run {
                appState.errorMessage = error.localizedDescription
                appState.meetingRecordingState = .error
                appState.meetingRecordingStartTime = nil
            }
        }

        setupMenu() // Update menu title
        NSLog("[DictateToBuffer] stopMeetingRecording: END")
    }

    @objc private func selectAutoDetect() {
        appState.useAutoDetect = true
        appState.selectedDeviceID = nil
        SettingsStorage.shared.useAutoDetect = true
        SettingsStorage.shared.selectedDeviceID = nil
        setupMenu()
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDevice else { return }
        appState.useAutoDetect = false
        appState.selectedDeviceID = device.id
        SettingsStorage.shared.useAutoDetect = false
        SettingsStorage.shared.selectedDeviceID = device.id
        setupMenu()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(appState)

            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Dictate to Buffer Settings"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating

            settingsWindow = window
        }

        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}
