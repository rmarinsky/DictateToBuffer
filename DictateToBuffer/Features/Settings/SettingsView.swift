import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AudioSettingsView()
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }

            MeetingSettingsView()
                .tabItem {
                    Label("Meetings", systemImage: "person.3")
                }

            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            APISettingsView()
                .tabItem {
                    Label("API", systemImage: "key")
                }

            LogsSettingsView()
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
        }
        .frame(width: 600, height: 650)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
