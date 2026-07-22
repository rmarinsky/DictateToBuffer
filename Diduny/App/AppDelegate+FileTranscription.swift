import Foundation

// MARK: - File Transcription

extension AppDelegate {
    func transcribeFiles() {
        if FileTranscriptionBatchService.shared.isProcessing {
            BatchTranscriptionWindowController.shared.showWindow()
        } else {
            BatchTranscriptionWindowController.shared.selectFilesForNewBatch()
        }
    }
}
