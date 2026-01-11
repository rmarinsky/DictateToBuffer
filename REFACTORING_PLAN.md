# Task: Modernize DictateToBuffer macOS App

You are refactoring a macOS menu bar dictation app. The app records audio, transcribes via Soniox API, and pastes results. Below is the complete list of changes to implement.

## Project Location
`/Users/rmarinskyi/PycharmProjects/DictateToBuffer`

## Context
- **Platform:** macOS 14.0+ (Sonoma)
- **Language:** Swift / SwiftUI
- **App Type:** Menu bar app (LSUIElement = YES)
- **Key Files:** See CLAUDE.md in project root for architecture details

---

## PHASE 1: Quick Wins (Do First)

### 1.1 Add @MainActor to AppState
**File:** `DictateToBuffer/App/AppState.swift`
- Add `@MainActor` attribute to `AppState` class
- This ensures all UI state mutations happen on main thread

### 1.2 Replace NSLog with os.Logger
**All Swift files**
- Create a new file `DictateToBuffer/Core/Utilities/Logger.swift` with:
```swift
import os

enum Log {
    static let app = Logger(subsystem: "com.dictate.buffer", category: "app")
    static let recording = Logger(subsystem: "com.dictate.buffer", category: "recording")
    static let transcription = Logger(subsystem: "com.dictate.buffer", category: "transcription")
    static let audio = Logger(subsystem: "com.dictate.buffer", category: "audio")
    static let permissions = Logger(subsystem: "com.dictate.buffer", category: "permissions")
}
```
- Replace all `NSLog("[DictateToBuffer]...` with `Log.app.info(...)`
- Replace all `NSLog("[Transcription]...` with `Log.transcription.info(...)`
- Replace all `NSLog("[AudioRecorder]...` with `Log.audio.info(...)`
- Replace all `NSLog("[AppState]...` with `Log.app.debug(...)`
- Replace all `NSLog("[PermissionManager]...` with `Log.permissions.info(...)`
- Replace all `NSLog("[ClipboardService]...` with `Log.app.info(...)`

### 1.3 Fix Force Unwrapped URLs
**File:** `DictateToBuffer/Core/Services/SonioxTranscriptionService.swift`
- Replace all `URL(string: "...")!` with guard statements
- Throw `TranscriptionError.invalidURL` (add this case to Errors.swift)

### 1.4 Remove Unused Code
**File:** `DictateToBuffer/App/AppDelegate.swift`
- Delete methods: `checkMicrophonePermission()`, `onMicrophonePermissionGranted()`, `onMicrophonePermissionDenied()` (lines ~85-147) - these are replaced by PermissionManager

**File:** `DictateToBuffer/Core/Services/AudioDeviceManager.swift`
- Delete unused variable `selfPtr` at line 252

### 1.5 Remove Redundant .receive(on: DispatchQueue.main)
**File:** `DictateToBuffer/App/AppDelegate.swift`
- In `setupBindings()`, remove `.receive(on: DispatchQueue.main)` from all three Combine subscriptions (lines 249, 258, 265)
- @Published already publishes on main thread

### 1.6 Use @AppStorage to Eliminate State Duplication
**File:** `DictateToBuffer/App/AppState.swift`
- Replace manual `useAutoDetect` and `selectedDeviceID` properties with @AppStorage:
```swift
@AppStorage("useAutoDetect") var useAutoDetect: Bool = false
@AppStorage("selectedDeviceID") var selectedDeviceID: Int = 0
```
- Update all places that manually sync AppState ↔ SettingsStorage (AppDelegate lines 774-778, 783-787)

---

## PHASE 2: SwiftUI Modernization

### 2.1 Migrate to MenuBarExtra (macOS 13+)
**File:** `DictateToBuffer/App/DictateToBufferApp.swift`
- Replace the EmptyView hack with proper MenuBarExtra:
```swift
@main
struct DictateToBufferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarIconView()
                .environmentObject(appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}
```
- Create new file `DictateToBuffer/Features/MenuBar/MenuBarContentView.swift` - extract menu content from AppDelegate.setupMenu()
- Create new file `DictateToBuffer/Features/MenuBar/MenuBarIconView.swift` - dynamic icon based on state
- Remove manual menu and settings window management from AppDelegate

### 2.2 Replace Timer with TimelineView
**File:** `DictateToBuffer/Features/Recording/RecordingIndicatorView.swift`
- Remove `@State private var timerTick` and `@State private var timer`
- Remove `startTimer()` and `stopTimer()` methods
- Replace the duration display with TimelineView:
```swift
TimelineView(.periodic(from: .now, by: 1.0)) { context in
    if appState.recordingState == .recording {
        Text(formattedDuration)
    }
}
```

### 2.3 Use SwiftUI Settings Scene
- Remove manual NSWindow creation for settings in AppDelegate (lines 790-815)
- Settings window now managed by SwiftUI Settings scene from 2.1

---

## PHASE 3: Async/Await Modernization

### 3.1 Convert PermissionManager to Full Async
**File:** `DictateToBuffer/Core/Storage/PermissionManager.swift`
- Replace callback-based `requestAllPermissions(completion:)` with:
```swift
func requestAllPermissions() async -> PermissionStatus
```
- Remove DispatchGroup usage
- Use async let for parallel permission requests
- Update AppDelegate to call with `Task { await ... }`

### 3.2 Replace DispatchQueue.main.asyncAfter with Task.sleep
**File:** `DictateToBuffer/App/AppDelegate.swift`
- Replace all `DispatchQueue.main.asyncAfter` calls for state transitions with:
```swift
Task {
    try? await Task.sleep(for: .seconds(1.5))
    if appState.recordingState == .success {
        appState.recordingState = .idle
    }
}
```

---

## PHASE 4: Architecture Refactoring

### 4.1 Extract RecordingCoordinator from AppDelegate
**Create:** `DictateToBuffer/Core/Coordinators/RecordingCoordinator.swift`
- Move all recording logic: `startRecording()`, `stopRecording()`, `toggleRecording()`, `performToggleRecording()`, `startRecordingIfIdle()`, `stopRecordingIfRecording()`
- Move meeting recording logic: `startMeetingRecording()`, `stopMeetingRecording()`, `toggleMeetingRecording()`, `performToggleMeetingRecording()`
- Inject services via init
- AppDelegate creates and holds reference to coordinator

### 4.2 Extract HotkeyCoordinator
**Create:** `DictateToBuffer/Core/Coordinators/HotkeyCoordinator.swift`
- Move hotkey setup and push-to-talk setup from AppDelegate
- Handle hotkey changed notifications internally
- Expose simple `start()` and `stop()` methods

### 4.3 Protocol-Based Dependency Injection
**Create:** `DictateToBuffer/Core/Protocols/` directory with:
- `SettingsStorageProtocol.swift`
- `KeychainManagerProtocol.swift`
- `TranscriptionServiceProtocol.swift`
- `AudioRecorderProtocol.swift`
- `ClipboardServiceProtocol.swift`

Make existing classes conform to these protocols. Update coordinators to depend on protocols, not concrete types.

---

## PHASE 5: Network & Error Handling

### 5.1 Add Retry Logic to SonioxTranscriptionService
**File:** `DictateToBuffer/Core/Services/SonioxTranscriptionService.swift`
- Create a generic retry helper:
```swift
private func withRetry<T>(maxAttempts: Int = 3, operation: () async throws -> T) async throws -> T
```
- Wrap `uploadFile`, `createTranscription` calls with retry
- Use exponential backoff (1s, 2s, 4s)

### 5.2 Add Request Timeout
- Add timeout to URLRequest: `request.timeoutInterval = 30`
- Add overall timeout for polling loop

---

## PHASE 6: Code Cleanup

### 6.1 Replace NotificationCenter with Combine
**Files:** `AppDelegate.swift`, `SettingsStorage.swift`
- Add Combine publishers to SettingsStorage for hotkey and push-to-talk key changes
- Replace NotificationCenter observers in AppDelegate with Combine subscriptions
- Remove Notification.Name extensions for these

### 6.2 Fix HotkeyService Static Instance Issue
**File:** `DictateToBuffer/Core/Services/HotkeyService.swift`
- Remove static sharedInstance pattern
- Use proper instance management that supports multiple hotkeys (one for recording, one for meetings)
- Consider rewriting with CGEvent-based approach

---

## Testing Checklist
After each phase, verify:
1. App builds without warnings
2. Recording flow works (hotkey → record → transcribe → paste)
3. Meeting recording works
4. Push-to-talk works
5. Settings window opens and saves preferences
6. Menu bar icon updates correctly
7. Audio device selection works

---

## Order of Implementation
1. Phase 1 (Quick Wins) - Safe, isolated changes
2. Phase 2.2 (TimelineView) - Isolated SwiftUI change
3. Phase 3 (Async) - Modernize concurrency
4. Phase 2.1 & 2.3 (MenuBarExtra) - Major SwiftUI restructure
5. Phase 4 (Architecture) - Extract coordinators
6. Phase 5 (Network) - Add reliability
7. Phase 6 (Cleanup) - Final polish

Start with Phase 1 and proceed incrementally, testing after each change.
