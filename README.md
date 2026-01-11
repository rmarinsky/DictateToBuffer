# DictateToBuffer

A native macOS menu bar app for voice dictation. Record your voice, get it transcribed via Soniox API, and automatically paste the text.

## Features

- **Voice Dictation** - Press hotkey, speak, release, text appears
- **Menu Bar App** - Lives in your menu bar, no dock icon
- **Global Hotkey** - Default: `Cmd+Shift+D`
- **Push-to-Talk** - Hold Caps Lock, Right Shift, or Right Option
- **Meeting Recording** - Capture system audio from Zoom, Meet, etc. (`Cmd+Shift+M`)
- **Auto-Paste** - Transcribed text automatically pastes to active app
- **Secure Storage** - API keys stored in macOS Keychain

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- [Homebrew](https://brew.sh) (for XcodeGen)
- [Soniox API key](https://console.soniox.com)

## Build & Install

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/DictateToBuffer.git
cd DictateToBuffer
```

### 2. Generate Xcode Project

```bash
./generate_project.sh
```

This installs XcodeGen (if needed) and generates `DictateToBuffer.xcodeproj`.

### 3. Open in Xcode

```bash
open DictateToBuffer.xcodeproj
```

### 4. Configure Signing

1. In Xcode, select the **DictateToBuffer** target
2. Go to **Signing & Capabilities**
3. Select your **Team** (or personal Apple ID)
4. Xcode will automatically manage signing

### 5. Build the App

**Option A: Build in Xcode**
- Press `Cmd+B` to build
- Or `Cmd+R` to build and run

**Option B: Build from Terminal**
```bash
xcodebuild -scheme DictateToBuffer -configuration Release build SYMROOT=./build
```

### 6. Install to Applications

After building, copy the app to your Applications folder:

**From Xcode build:**
```bash
cp -r ~/Library/Developer/Xcode/DerivedData/DictateToBuffer-*/Build/Products/Release/DictateToBuffer.app /Applications/
```

**From terminal build:**
```bash
cp -r ./build/Release/DictateToBuffer.app /Applications/
```

Or manually:
1. In Xcode: **Product** → **Show Build Folder in Finder**
2. Navigate to `Products/Release/`
3. Drag `DictateToBuffer.app` to `/Applications`

## First Launch Setup

### 1. Launch the App

```bash
open /Applications/DictateToBuffer.app
```

Or double-click in Finder. The app icon appears in your menu bar.

### 2. Grant Permissions

The app will request these permissions:

| Permission | Why Needed | How to Grant |
|------------|-----------|--------------|
| **Microphone** | Record your voice | Click "Allow" when prompted |
| **Accessibility** | Auto-paste text (Cmd+V simulation) | System Settings → Privacy & Security → Accessibility → Enable DictateToBuffer |
| **Screen Recording** | Meeting recording (system audio) | System Settings → Privacy & Security → Screen Recording → Enable DictateToBuffer |

### 3. Add Soniox API Key

1. Click the menu bar icon
2. Select **Settings**
3. Go to **API** tab
4. Enter your [Soniox API key](https://console.soniox.com)
5. Click **Test Connection** to verify

## Usage

### Voice Dictation

| Action | Method |
|--------|--------|
| Start/Stop Recording | Click menu bar icon |
| Start/Stop Recording | Press `Cmd+Shift+D` |
| Push-to-Talk | Hold `Caps Lock`, `Right Shift`, or `Right Option` |

1. Activate recording
2. Speak clearly
3. Stop recording
4. Text is transcribed and pasted automatically

### Meeting Recording

| Action | Method |
|--------|--------|
| Start/Stop Meeting Recording | Press `Cmd+Shift+M` |
| Start/Stop Meeting Recording | Menu → Record Meeting |

Records system audio (Zoom, Google Meet, Teams, etc.) and transcribes when stopped.

### Settings

Access via menu bar icon → **Settings**:

- **General** - Hotkey, push-to-talk key, auto-paste toggle
- **Audio** - Microphone selection, audio quality
- **Meetings** - Audio source (system only / system + mic)
- **API** - Soniox API key

## Troubleshooting

### App doesn't appear in menu bar
- Check if app is running: `ps aux | grep DictateToBuffer`
- Try relaunching the app

### Microphone not working
- System Settings → Privacy & Security → Microphone → Ensure DictateToBuffer is enabled
- Try selecting a different audio device in Settings → Audio

### Auto-paste not working
- System Settings → Privacy & Security → Accessibility → Enable DictateToBuffer
- Restart the app after granting permission

### Meeting recording not capturing audio
- System Settings → Privacy & Security → Screen Recording → Enable DictateToBuffer
- Restart the app after granting permission

### "API key invalid" error
- Verify your key at [console.soniox.com](https://console.soniox.com)
- Re-enter the key in Settings → API

## Uninstall

```bash
# Remove app
rm -rf /Applications/DictateToBuffer.app

# Remove preferences (optional)
defaults delete com.dictate.buffer

# Remove keychain items (optional)
security delete-generic-password -s "com.dictate.buffer.soniox" 2>/dev/null
```

## License

MIT
