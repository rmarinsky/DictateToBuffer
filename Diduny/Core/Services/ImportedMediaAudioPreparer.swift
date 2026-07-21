import AVFoundation
import Foundation

/// Converts imported media into a compact audio-only file before it can cross
/// the app's network boundary.
final class ImportedMediaAudioPreparer {
    static let maximumDurationSeconds: TimeInterval = 300 * 60

    struct PreparedAudio {
        let fileURL: URL
        let durationSeconds: TimeInterval

        func removeTemporaryFile() {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    enum PreparationError: LocalizedError, Equatable {
        case noAudioTrack
        case invalidDuration
        case durationLimitExceeded(maximumMinutes: Int)
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                "The selected file does not contain an audio track."
            case .invalidDuration:
                "The selected file has an invalid duration."
            case let .durationLimitExceeded(maximumMinutes):
                "The selected file is longer than the \(maximumMinutes)-minute transcription limit."
            case let .extractionFailed(message):
                "Could not extract audio: \(message)"
            }
        }
    }

    private let fileManager: FileManager
    private let temporaryDirectory: URL

    init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    func prepare(sourceURL: URL) async throws -> PreparedAudio {
        try Task.checkCancellation()

        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        try Self.validate(durationSeconds: durationSeconds)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw PreparationError.noAudioTrack
        }

        let outputURL = temporaryDirectory
            .appendingPathComponent("diduny-import-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        do {
            try await extractAudio(from: asset, to: outputURL)
            try Task.checkCancellation()
            return PreparedAudio(fileURL: outputURL, durationSeconds: durationSeconds)
        } catch {
            try? fileManager.removeItem(at: outputURL)
            if error is CancellationError {
                throw error
            }
            if let preparationError = error as? PreparationError {
                throw preparationError
            }
            throw PreparationError.extractionFailed(error.localizedDescription)
        }
    }

    static func validate(durationSeconds: TimeInterval) throws {
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw PreparationError.invalidDuration
        }
        guard durationSeconds <= maximumDurationSeconds else {
            throw PreparationError.durationLimitExceeded(
                maximumMinutes: Int(maximumDurationSeconds / 60)
            )
        }
    }

    private func extractAudio(
        from asset: AVAsset,
        to outputURL: URL
    ) async throws {
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw PreparationError.extractionFailed(
                "The selected media format cannot be converted to audio."
            )
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(
                        throwing: PreparationError.extractionFailed(
                            exporter.error?.localizedDescription
                                ?? "Audio export did not complete."
                        )
                    )
                }
            }
        }
    }
}
