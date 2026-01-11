import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var audioDeviceManager: AudioDeviceManager
    @Environment(\.openSettings) private var openSettings

    var onToggleRecording: @MainActor () -> Void
    var onToggleMeetingRecording: @MainActor () -> Void
    var onSelectAutoDetect: @MainActor () -> Void
    var onSelectDevice: @MainActor (AudioDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recording toggle
            Button(action: onToggleRecording) {
                HStack {
                    Text(recordingButtonTitle)
                    Spacer()
                    Text("⌘⇧D")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            // Meeting recording toggle
            Button(action: onToggleMeetingRecording) {
                HStack {
                    Text(meetingButtonTitle)
                    Spacer()
                    Text("⌘⇧M")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            // Audio device menu
            Menu("Audio Device") {
                Button(action: onSelectAutoDetect) {
                    HStack {
                        Text("Auto-detect")
                        if appState.useAutoDetect {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(audioDeviceManager.availableDevices, id: \.id) { device in
                    Button(action: { onSelectDevice(device) }) {
                        HStack {
                            Text(device.name)
                            if !appState.useAutoDetect && appState.selectedDeviceID == device.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            // Settings
            Button(action: { openSettings() }) {
                HStack {
                    Text("Settings...")
                    Spacer()
                    Text("⌘,")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            // Quit
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
    }

    private var recordingButtonTitle: String {
        switch appState.recordingState {
        case .idle:
            return "Start Recording"
        case .recording:
            return "Stop Recording"
        case .processing:
            return "Processing..."
        case .success:
            return "Done"
        case .error:
            return "Error"
        }
    }

    private var meetingButtonTitle: String {
        switch appState.meetingRecordingState {
        case .idle:
            return "Record Meeting"
        case .recording:
            return "Stop Meeting Recording"
        case .processing:
            return "Processing Meeting..."
        case .success:
            return "Meeting Done"
        case .error:
            return "Meeting Error"
        }
    }
}
