# CLAUDE.md - Project Context for Claude

## Project Overview

**DictateToBuffer** is a native macOS menu bar application for voice dictation. It records audio, transcribes it using the Soniox API, and pastes the result.

- **Platform:** macOS 14.0+ (Sonoma)
- **Language:** Swift / SwiftUI
- **App Type:** Menu bar app (LSUIElement = YES, no dock icon)
- **Transcription Service:** Soniox only (async STT API)

## Key Architecture

### Entry Point & Orchestration
- `DictateToBufferApp.swift` - SwiftUI app entry point
- `AppDelegate.swift` - Main orchestrator: menu bar, hotkey handling, recording flow
- `AppState.swift` - Shared observable state (recordingState, selectedDevice, etc.)

### Recording Flow
1. User triggers via:
   - Hotkey (⌘⇧D)
   - Left-click menu bar icon
   - Push-to-talk key (Caps Lock, Right Shift, or Right Option)
2. `AppDelegate.toggleRecording()` → `startRecording()` or `stopRecording()`
3. `AudioRecorderService` captures audio to WAV
4. `SonioxTranscriptionService.transcribe()` sends to API
5. `ClipboardService` copies result and optionally pastes

### Push-to-Talk Mode
- Hold key to record, release to stop and transcribe
- Options: Caps Lock (keyCode 57), Right Shift (60), Right Option (61)
- Uses `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`

### Meeting Recording (macOS 13.0+)
- Records system audio for meetings (Zoom, Meet, Teams, etc.)
- Uses ScreenCaptureKit for system audio capture
- Supports long recordings (1+ hour)
- Trigger: ⌘⇧M or Menu → Record Meeting
- Audio sources: System Only or System + Microphone
- Requires Screen Recording permission

### Services (DictateToBuffer/Core/Services/)
| Service | Purpose |
|---------|---------|
| `AudioDeviceManager` | Lists input devices, auto-detects best microphone |
| `AudioRecorderService` | Records audio using AVAudioEngine |
| `SonioxTranscriptionService` | 4-step async transcription: upload → create job → poll → get text |
| `ClipboardService` | Copy to clipboard, simulate Cmd+V paste |
| `HotkeyService` | Global hotkey registration using Carbon |
| `PushToTalkService` | Monitor modifier keys (Caps Lock/Right Shift/Right Option) for push-to-talk |
| `SystemAudioCaptureService` | Capture system audio using ScreenCaptureKit (macOS 13+) |
| `MeetingRecorderService` | Orchestrate meeting recording with system audio capture |

### Soniox API Integration
- **Base URL:** `https://api.soniox.com/v1`
- **Model:** `stt-async-preview`
- **Flow:** POST /files → POST /transcriptions → GET /transcriptions/{id} (poll) → GET /transcriptions/{id}/transcript
- **Auth:** Bearer token in Authorization header

### Storage (DictateToBuffer/Core/Storage/)
- `KeychainManager` - Stores Soniox API key securely
- `SettingsStorage` - UserDefaults for preferences (audio quality, hotkey, auto-paste, etc.)

### UI (DictateToBuffer/Features/)
- `SettingsView` - TabView with General, Audio, Meetings, API tabs
- `APISettingsView` - Soniox API key input with test connection button
- `MeetingSettingsView` - Meeting audio source selection
- `RecordingIndicatorView` - Floating pill showing recording/processing status

## State Machine
```
RecordingState: idle → recording → processing → success/error → idle
MeetingRecordingState: idle → recording → processing → success/error → idle
```

## Key Files to Edit

| Task | Files |
|------|-------|
| Change transcription logic | `SonioxTranscriptionService.swift` |
| Modify recording behavior | `AudioRecorderService.swift`, `AppDelegate.swift` |
| Add settings | `SettingsStorage.swift`, relevant settings view |
| Change hotkey | `HotkeyService.swift`, `GeneralSettingsView.swift` |
| Modify menu bar | `AppDelegate.setupMenu()` |

## Build

```bash
# Using XcodeGen
./generate_project.sh
open DictateToBuffer.xcodeproj

# Or manual xcodebuild
xcodebuild -scheme DictateToBuffer -configuration Debug build
```

## Required Permissions
- Microphone (NSMicrophoneUsageDescription)
- Screen Recording (for meeting audio capture via ScreenCaptureKit)
- Accessibility (for auto-paste Cmd+V simulation)
- Keychain (for API key storage)
- Network (for Soniox API)

## Logging
App uses `NSLog()` with prefixes:
- `[DictateToBuffer]` - AppDelegate flow
- `[Transcription]` - Soniox API calls
- `[AppState]` - State changes

## Common Issues
- AudioHardware warnings (ID 98) - Harmless CoreAudio cleanup messages
- FBSWorkspaceScenesClient errors - macOS Control Center internal errors, not from this app
