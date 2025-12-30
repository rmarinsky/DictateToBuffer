import SwiftUI

struct AudioSettingsView: View {
    @StateObject private var deviceManager = AudioDeviceManager()
    @State private var useAutoDetect = SettingsStorage.shared.useAutoDetect
    @State private var selectedDeviceID: AudioDeviceID? = SettingsStorage.shared.selectedDeviceID
    @State private var audioQuality = SettingsStorage.shared.audioQuality

    var body: some View {
        Form {
            Section {
                Picker("Quality", selection: $audioQuality) {
                    ForEach(AudioQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                .onChange(of: audioQuality) { _, newValue in
                    SettingsStorage.shared.audioQuality = newValue
                }
            } header: {
                Text("Audio Quality")
            }

            Section {
                // Auto-detect option
                HStack {
                    RadioButton(isSelected: useAutoDetect) {
                        useAutoDetect = true
                        selectedDeviceID = nil
                        saveSelection()
                    }
                    Text("Auto-detect best device")
                        .foregroundColor(useAutoDetect ? .primary : .secondary)
                    Spacer()
                    if useAutoDetect {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    useAutoDetect = true
                    selectedDeviceID = nil
                    saveSelection()
                }

                Divider()

                // Device list
                ForEach(deviceManager.availableDevices) { device in
                    HStack {
                        RadioButton(isSelected: !useAutoDetect && selectedDeviceID == device.id) {
                            useAutoDetect = false
                            selectedDeviceID = device.id
                            saveSelection()
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .foregroundColor(!useAutoDetect && selectedDeviceID == device.id ? .primary : .secondary)

                            if device.isDefault {
                                Text("System Default")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if !useAutoDetect && selectedDeviceID == device.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        useAutoDetect = false
                        selectedDeviceID = device.id
                        saveSelection()
                    }
                }
            } header: {
                Text("Input Device")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func saveSelection() {
        SettingsStorage.shared.useAutoDetect = useAutoDetect
        SettingsStorage.shared.selectedDeviceID = selectedDeviceID
    }
}

// MARK: - Radio Button

struct RadioButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary, lineWidth: 2)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .padding(3)
                )
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AudioSettingsView()
        .frame(width: 450, height: 350)
}
