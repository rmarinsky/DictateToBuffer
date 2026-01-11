# DictateToBuffer Improvement Prompts

Each section below is a self-contained prompt for a separate Claude Code session. Copy the entire section (including context) to start a focused improvement task.

---

## 1. Thread Safety - HotkeyService Singleton Fix

**Estimated complexity:** Low
**Files involved:** `DictateToBuffer/Core/Services/HotkeyService.swift`

### Prompt:
```
Fix thread safety issue in HotkeyService. The current implementation uses a problematic static shared instance pattern:

Current issue in HotkeyService.swift:
- `private static var sharedInstance: HotkeyService?` can break if multiple instances are created
- No thread synchronization for shared state

Requirements:
1. Convert to proper singleton pattern using `static let shared = HotkeyService()`
2. Add thread safety with a serial DispatchQueue for registration/unregistration
3. Add guard against double registration
4. Ensure proper cleanup in deinit

The service uses Carbon API (RegisterEventHotKey, InstallEventHandler) for global hotkeys.
Keep the existing callback-based design with `onHotkeyPressed` closure.
```

---

## 2. Network Resilience - API Retry Logic

**Estimated complexity:** Medium
**Files involved:** `DictateToBuffer/Core/Services/SonioxTranscriptionService.swift`

### Prompt:
```
Add network resilience to SonioxTranscriptionService.swift. Current issues:
- No retry logic for transient API failures (timeouts, 5xx errors)
- Uses URLSession defaults without explicit timeout configuration
- Single 60-second window for transcription completion

Requirements:
1. Add configurable URLSession with explicit timeouts:
   - Connection timeout: 10 seconds
   - Resource timeout: 30 seconds per request

2. Implement exponential backoff retry for transient errors:
   - Retry on: timeout, 429 (rate limit), 500, 502, 503, 504
   - Max retries: 3
   - Backoff: 1s, 2s, 4s
   - Don't retry on: 400, 401, 403, 404

3. Add retry wrapper function:
   ```swift
   private func withRetry<T>(
       maxAttempts: Int = 3,
       operation: () async throws -> T
   ) async throws -> T
   ```

4. Apply retry to: uploadFile(), createTranscription(), getTranscriptionStatus(), getTranscript()

The service uses 4-step async flow: upload → create job → poll status → get transcript.
API base URL: https://api.soniox.com/v1
Keep existing error types in Errors.swift.
```

---

## 3. Configuration Management - Extract Hardcoded Values

**Estimated complexity:** Low
**Files involved:**
- `DictateToBuffer/Core/Services/SonioxTranscriptionService.swift`
- `DictateToBuffer/Core/Services/AudioRecorderService.swift`
- `DictateToBuffer/Core/Services/SystemAudioCaptureService.swift`
- `DictateToBuffer/Core/Storage/SettingsStorage.swift`

### Prompt:
```
Extract hardcoded configuration values into a centralized configuration. Current hardcoded values:

In SonioxTranscriptionService.swift:
- pollingInterval: 1.0 seconds
- maxPollingAttempts: 60 (60 second timeout)
- API model: "stt-async-preview"

In AudioRecorderService.swift:
- Temp file pattern: "dictate_{UUID}.wav"
- Level monitoring interval: 0.1 seconds

In SystemAudioCaptureService.swift:
- Sample rate: 48000 Hz
- Channel count: 2
- Temp file pattern: "meeting_{timestamp}.wav"

Requirements:
1. Create `DictateToBuffer/Core/Config/AppConfiguration.swift`:
   ```swift
   enum AppConfiguration {
       enum Transcription {
           static let pollingInterval: TimeInterval = 1.0
           static let maxPollingAttempts = 60
           static let model = "stt-async-preview"
       }
       enum Audio {
           static let levelMonitoringInterval: TimeInterval = 0.1
           static let systemAudioSampleRate: Double = 48000
           static let systemAudioChannels: Int = 2
       }
       enum TempFiles {
           static let dictationPrefix = "dictate_"
           static let meetingPrefix = "meeting_"
       }
   }
   ```

2. Replace all hardcoded values with references to AppConfiguration
3. Add to project.yml sources if using XcodeGen
```

---

## 4. Concurrent Recording Guard

**Estimated complexity:** Low
**Files involved:** `DictateToBuffer/App/AppDelegate.swift`

### Prompt:
```
Add guards against concurrent recording operations in AppDelegate.swift.

Current issue:
- State check exists but no mutex/semaphore
- User could potentially trigger multiple recordings via different input methods (hotkey + menu + push-to-talk)

Requirements:
1. Add an actor-based lock or use Swift's actor isolation properly:
   ```swift
   private var isOperationInProgress = false
   ```

2. Guard all entry points in AppDelegate:
   - toggleRecording()
   - toggleMeetingRecording()
   - startRecording()
   - stopRecording()

3. Ensure atomic state transitions:
   - Check state AND set lock atomically
   - Release lock on completion or error

4. Add logging when operation is blocked due to concurrent attempt

AppDelegate is already @MainActor, so leverage that for synchronization.
Don't change the public API or break existing hotkey/menu/push-to-talk flows.
```

---

## 5. Meeting Recording - System + Microphone Audio Mixing

**Estimated complexity:** High
**Files involved:**
- `DictateToBuffer/Core/Services/MeetingRecorderService.swift`
- `DictateToBuffer/Core/Services/SystemAudioCaptureService.swift`
- `DictateToBuffer/Core/Services/AudioRecorderService.swift`

### Prompt:
```
Implement proper audio mixing for meeting recording when audioSource == .systemPlusMicrophone.

Current state:
- SystemAudioCaptureService captures system audio via ScreenCaptureKit
- AudioRecorderService captures microphone via AVAudioRecorder
- MeetingRecorderService has a comment: "For proper mixing, we'd need a more complex setup"
- Currently only system audio is captured even when .systemPlusMicrophone is selected

Requirements:
1. Create new service `AudioMixerService.swift` that:
   - Takes two audio sources (system + mic)
   - Uses AVAudioEngine with mixer node
   - Outputs combined audio to single file

2. Architecture approach:
   ```
   SystemAudioCaptureService → AVAudioPCMBuffer →┐
                                                  ├→ AVAudioMixerNode → AVAudioFile
   Microphone (AVAudioEngine input) ────────────→┘
   ```

3. Update MeetingRecorderService to:
   - Use AudioMixerService when audioSource == .systemPlusMicrophone
   - Use SystemAudioCaptureService alone when audioSource == .systemOnly

4. Handle sample rate conversion if needed (mic may differ from 48kHz system audio)

5. Ensure proper synchronization of audio streams

Use AVAudioEngine for real-time mixing. Output format should match current: WAV, 48kHz, stereo.
```

---

## 6. Audio Quality Settings Alignment

**Estimated complexity:** Low
**Files involved:**
- `DictateToBuffer/Core/Models/AudioQuality.swift`
- `DictateToBuffer/Core/Services/SystemAudioCaptureService.swift`

### Prompt:
```
Align audio quality settings between dictation and meeting recording.

Current inconsistency:
- AudioQuality enum for dictation:
  - high: 22050 Hz (unusual, typically 44.1kHz for "high")
  - medium: 16000 Hz
  - low: 12000 Hz
- SystemAudioCaptureService hardcoded to 48000 Hz

Requirements:
1. Review and update AudioQuality.swift:
   - high: 44100 Hz (CD quality, standard "high")
   - medium: 22050 Hz (half CD, good for speech)
   - low: 16000 Hz (telephony, optimized for speech recognition)

2. Add quality setting support to SystemAudioCaptureService:
   - Accept AudioQuality parameter in startCapture()
   - Map quality to appropriate sample rate

3. Update MeetingSettingsView to include audio quality selection for meetings

4. Consider: Soniox API may have optimal input format - check if 16kHz mono is preferred for transcription accuracy vs file size

Note: Changes to sample rates may affect transcription quality. Test with Soniox API after changes.
```

---

## 7. Device Persistence and Recovery

**Estimated complexity:** Medium
**Files involved:**
- `DictateToBuffer/Core/Services/AudioDeviceManager.swift`
- `DictateToBuffer/Core/Storage/SettingsStorage.swift`
- `DictateToBuffer/App/AppDelegate.swift`

### Prompt:
```
Improve audio device selection persistence and recovery.

Current issues:
- If selected device is removed, silently falls back to default
- No user notification when device changes
- Device selection stored by ID which may change across reboots

Requirements:
1. Persist device by UID (stable identifier) instead of AudioDeviceID:
   - AudioDeviceID is session-specific, changes across reboots
   - Use kAudioDevicePropertyDeviceUID for persistence

2. Add device change detection in AudioDeviceManager:
   ```swift
   var onDeviceDisconnected: ((AudioDevice) -> Void)?
   var onDeviceReconnected: ((AudioDevice) -> Void)?
   ```

3. Update SettingsStorage:
   - Store device UID string instead of device ID
   - Add migration for existing settings

4. Update AppDelegate to handle device events:
   - Show notification when selected device disconnects
   - Auto-restore when device reconnects
   - Update UI to show current device status

5. Add visual indicator in AudioSettingsView when selected device is unavailable

CoreAudio listener for device changes already exists (kAudioHardwarePropertyDevices).
Extend it to track specific device connection state.
```

---

## 8. App Sandboxing and Entitlements

**Estimated complexity:** Medium
**Files involved:**
- `DictateToBuffer/Resources/DictateToBuffer.entitlements`
- `project.yml` (XcodeGen config)

### Prompt:
```
Configure proper entitlements for App Store distribution readiness.

Current state:
- Entitlements file is empty: <dict/>
- App runs with automatic code signing, no sandboxing
- Required permissions: Microphone, Accessibility, Screen Recording, Network

Requirements:
1. Update DictateToBuffer.entitlements with required capabilities:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.security.app-sandbox</key>
       <true/>
       <key>com.apple.security.device.audio-input</key>
       <true/>
       <key>com.apple.security.network.client</key>
       <true/>
       <key>com.apple.security.temporary-exception.apple-events</key>
       <array>
           <string>com.apple.systemevents</string>
       </array>
   </dict>
   </plist>
   ```

2. Note: Some features may not work in sandbox:
   - Accessibility (CGEvent paste simulation) - needs exception or alternative
   - ScreenCaptureKit - may need com.apple.security.temporary-exception.screen-capture

3. Test each permission after enabling sandbox:
   - Microphone recording
   - Network API calls
   - Clipboard paste simulation
   - Screen/system audio capture

4. Document any sandbox-incompatible features that need alternative approaches

If full sandboxing breaks functionality, document which entitlements are needed and why.
Consider: App may need to remain non-sandboxed for Accessibility features.
```

---

## 9. Error Handling Enhancement

**Estimated complexity:** Low
**Files involved:**
- `DictateToBuffer/Core/Models/Errors.swift`
- `DictateToBuffer/Core/Services/SonioxTranscriptionService.swift`
- `DictateToBuffer/App/AppDelegate.swift`

### Prompt:
```
Enhance error handling with more specific error types and user-friendly messages.

Current state in Errors.swift:
- Generic TranscriptionError with few cases
- Some errors use string messages that aren't localized

Requirements:
1. Expand TranscriptionError enum:
   ```swift
   enum TranscriptionError: LocalizedError {
       case noApiKey
       case invalidApiKey
       case networkTimeout
       case networkUnavailable
       case rateLimited(retryAfter: TimeInterval?)
       case serverError(statusCode: Int)
       case uploadFailed(reason: String)
       case transcriptionFailed(reason: String)
       case transcriptionTimeout
       case emptyTranscription
       case invalidResponse

       var errorDescription: String? { ... }
       var recoverySuggestion: String? { ... }
   }
   ```

2. Add AudioError enum:
   ```swift
   enum AudioError: LocalizedError {
       case permissionDenied
       case deviceNotFound
       case deviceDisconnected
       case recordingFailed(reason: String)
       case invalidFormat
   }
   ```

3. Update SonioxTranscriptionService to throw specific errors based on HTTP status codes

4. Update AppDelegate error handling to show appropriate user messages:
   - Different icon/notification for different error types
   - Include recovery suggestion in notification

5. Add error analytics logging (just os.Logger, not external service)
```

---

## 10. Unit Tests Foundation

**Estimated complexity:** Medium
**Files involved:**
- `DictateToBufferTests/` (new test files)
- Services to test

### Prompt:
```
Create unit test foundation for core services. The project has DictateToBufferTests target but needs actual tests.

Requirements:
1. Create mock/protocol abstractions for testability:
   - `TranscriptionServiceProtocol` for SonioxTranscriptionService
   - `AudioRecorderProtocol` for AudioRecorderService
   - `ClipboardServiceProtocol` for ClipboardService

2. Create test files:
   - `SonioxTranscriptionServiceTests.swift`
   - `AudioDeviceManagerTests.swift`
   - `SettingsStorageTests.swift`
   - `AppStateTests.swift`

3. Test cases for SonioxTranscriptionService:
   - Successful transcription flow (mock network)
   - API key validation
   - Timeout handling
   - Error response parsing
   - Empty transcription handling

4. Test cases for AppState:
   - State transitions (idle → recording → processing → success)
   - Error state handling
   - Meeting recording state independence

5. Test cases for SettingsStorage:
   - Save/load preferences
   - Default values
   - Migration handling

Use XCTest framework. Create URLProtocol mock for network tests.
Don't test UI or Carbon API (those need integration tests).
```

---

## Usage Instructions

1. **Copy one section** at a time into a new Claude Code session
2. **Start with low complexity** items (1, 3, 4, 6, 9) for quick wins
3. **Save medium/high complexity** items (2, 5, 7, 8, 10) for dedicated sessions
4. **Test after each change** - run build and manual testing
5. **Commit after each improvement** - keep changes atomic

## Priority Order (Recommended)

1. **Thread Safety (1)** - Prevents potential crashes
2. **Concurrent Recording Guard (4)** - Prevents user confusion
3. **Configuration Management (3)** - Foundation for other changes
4. **Error Handling (9)** - Better user experience
5. **Network Resilience (2)** - Reliability improvement
6. **Audio Quality Alignment (6)** - Consistency fix
7. **Device Persistence (7)** - UX improvement
8. **Unit Tests (10)** - Quality foundation
9. **Entitlements (8)** - Distribution prep
10. **Audio Mixing (5)** - Feature completion (most complex)
