import Foundation

// MARK: - File Transcription

extension AppDelegate {
    func batchFilesAndURLs() {
        MainWindowController.shared.requestBatchComposer()
        MainWindowController.shared.showWindow()
    }
}
