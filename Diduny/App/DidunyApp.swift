import SwiftUI

@main
struct DidunyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                audioDeviceManager: appDelegate.audioDeviceManager,
                onToggleRecording: { appDelegate.toggleRecording() },
                onToggleTranslationRecording: { appDelegate.toggleTranslationRecording() },
                onToggleMeetingRecording: { appDelegate.toggleMeetingRecording() },
                onToggleMeetingTranslationRecording: { appDelegate.toggleMeetingTranslationRecording() },
                onTranscribeFiles: { appDelegate.transcribeFiles() },
                onTranscribeURL: { appDelegate.transcribeURL() },
                onOpenMainWindow: { section in appDelegate.openMainWindow(section: section) },
                onCheckForUpdates: { appDelegate.updaterManager.checkForUpdates() }
            )
            .environment(appDelegate.appState)
        } label: {
            MenuBarIconView()
                .environment(appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Transcribe URL…") {
                    appDelegate.transcribeURL()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }
    }
}
