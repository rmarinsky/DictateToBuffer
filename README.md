# Dictate to Buffer - macOS App

Native macOS menu bar application for voice dictation with Soniox transcription.

## Features

- Menu bar app with global hotkey (⌘⇧D)
- Auto-detect best microphone or manual selection
- Minimal floating recording indicator
- API keys stored securely in macOS Keychain
- Auto-paste transcribed text

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Soniox API key ([create one at Soniox Console](https://console.soniox.com) - see [documentation](https://soniox.com/docs))

## Project Setup

### Option 1: Create Xcode Project Manually

1. Open Xcode
2. File → New → Project
3. Choose **macOS** → **App**
4. Configure:
   - Product Name: `DictateToBuffer`
   - Team: Your team
   - Organization Identifier: `com.dictate`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck "Include Tests"

5. After project creation:
   - Delete the auto-generated `ContentView.swift`
   - Drag all files from `DictateToBuffer/` folder into the Xcode project
   - In Project Settings → Signing & Capabilities:
     - Add "Audio Input" capability
     - Add "Keychain Sharing" capability
     - Add "Network (Client)" capability

6. Configure Info.plist:
   - Set `LSUIElement` = `YES` (menu bar app, no dock icon)
   - Add `NSMicrophoneUsageDescription`

7. Build & Run (⌘R)

### Option 2: Generate Xcode Project with Script

```bash
cd /Users/rmarinskyi/PycharmProjects/DictateToBuffer
./generate_project.sh
```

## Project Structure

```
DictateToBuffer/
├── App/
│   ├── DictateToBufferApp.swift    # Entry point
│   ├── AppDelegate.swift           # Menu bar & orchestration
│   └── AppState.swift              # Shared state
│
├── Features/
│   ├── Recording/
│   │   └── RecordingIndicatorView.swift  # Floating pill
│   └── Settings/
│       ├── SettingsView.swift      # Main settings
│       ├── GeneralSettingsView.swift
│       ├── AudioSettingsView.swift
│       └── APISettingsView.swift
│
├── Core/
│   ├── Models/
│   │   ├── AudioDevice.swift
│   │   ├── AudioQuality.swift
│   │   ├── Errors.swift
│   │   └── KeyCombo.swift
│   │
│   ├── Services/
│   │   ├── AudioDeviceManager.swift
│   │   ├── AudioRecorderService.swift
│   │   ├── SonioxTranscriptionService.swift
│   │   ├── ClipboardService.swift
│   │   └── HotkeyService.swift
│   │
│   └── Storage/
│       ├── KeychainManager.swift
│       └── SettingsStorage.swift
│
├── Utilities/
│   └── NotificationManager.swift
│
└── Resources/
    ├── Info.plist
    ├── DictateToBuffer.entitlements
    └── Assets.xcassets/
```

## Usage

1. Launch the app (appears in menu bar as 🎙️)
2. Click menu bar icon → Settings → Add Soniox API key
3. Select audio device or use Auto-detect
4. Press ⌘⇧D or click menu bar icon to start recording
5. Press again to stop → text is transcribed and pasted

## Permissions Required

- **Microphone** - For audio recording
- **Accessibility** - For auto-paste (Cmd+V simulation)
- **Keychain** - For secure API key storage

## Development

### Build
```bash
xcodebuild -scheme DictateToBuffer -configuration Debug build
```

### Run
```bash
open build/Debug/DictateToBuffer.app
```

## License

MIT
