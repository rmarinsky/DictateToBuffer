import SwiftUI

@main
struct DictateToBufferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app - no main window
        // Settings opened via AppDelegate.openSettings()
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
