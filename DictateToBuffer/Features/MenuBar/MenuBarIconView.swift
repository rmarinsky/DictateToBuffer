import SwiftUI

struct MenuBarIconView: View {
    @EnvironmentObject var appState: AppState

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
        .environmentObject(AppState())
}
