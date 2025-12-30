import SwiftUI

struct MeetingSettingsView: View {
    @State private var audioSource = SettingsStorage.shared.meetingAudioSource

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Audio Source")
                        .font(.headline)

                    ForEach(MeetingAudioSource.allCases, id: \.self) { source in
                        HStack {
                            Image(systemName: audioSource == source ? "circle.inset.filled" : "circle")
                                .foregroundColor(audioSource == source ? .accentColor : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName)
                                Text(source.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            audioSource = source
                            SettingsStorage.shared.meetingAudioSource = source
                        }
                    }
                }
            } header: {
                Text("Meeting Recording")
            } footer: {
                Text("Meeting recording captures system audio for transcribing calls and meetings. Requires Screen Recording permission.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hotkey: ⌘⇧M")
                        .font(.subheadline)

                    Text("Or use Menu → Record Meeting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("How to Use")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Supports recordings up to 1+ hour", systemImage: "clock")
                    Label("Transcription starts after you stop", systemImage: "text.bubble")
                    Label("Result copied to clipboard", systemImage: "doc.on.clipboard")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            } header: {
                Text("Features")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    MeetingSettingsView()
        .frame(width: 450, height: 400)
}
