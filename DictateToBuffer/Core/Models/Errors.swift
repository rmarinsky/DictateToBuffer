import Foundation

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case networkError(Error)
    case apiError(String)
    case invalidResponse
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Please add your Soniox API key in Settings"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .emptyTranscription:
            return "No speech detected"
        }
    }
}

enum AudioError: LocalizedError {
    case noInputDevice
    case permissionDenied
    case recordingFailed(String)
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device found"
        case .permissionDenied:
            return "Microphone permission denied. Please enable in System Settings."
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .deviceNotFound:
            return "Selected audio device not found"
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed
    case readFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Failed to save to Keychain"
        case .readFailed:
            return "Failed to read from Keychain"
        case .deleteFailed:
            return "Failed to delete from Keychain"
        }
    }
}
