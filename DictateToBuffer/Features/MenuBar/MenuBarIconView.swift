import SwiftUI

struct MenuBarIconView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        Text(iconText)
    }

    private var iconText: String {
        // Meeting recording takes priority
        if appState.meetingRecordingState == .recording {
            return "🎙️"
        }
        if appState.meetingRecordingState == .processing {
            return "⏳"
        }

        // Translation recording
        switch appState.translationRecordingState {
        case .recording:
            return "🔴"
        case .processing:
            return "⏳"
        case .success:
            return "✅"
        case .error:
            return "❌"
        case .idle:
            break
        }

        // Regular recording
        switch appState.recordingState {
        case .idle:
            if appState.meetingRecordingState == .success {
                return "✅"
            } else if appState.meetingRecordingState == .error {
                return "❌"
            }
            return "🥒"
        case .recording:
            return "🔴"
        case .processing:
            return "⏳"
        case .success:
            return "✅"
        case .error:
            return "❌"
        }
    }
}

#Preview {
    MenuBarIconView()
        .environment(AppState())
}
