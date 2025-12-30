import Foundation

enum AudioQuality: String, CaseIterable, Codable {
    case high
    case medium
    case low

    var sampleRate: Double {
        switch self {
        case .high: return 22050
        case .medium: return 16000
        case .low: return 12000
        }
    }

    var bitrate: Int {
        switch self {
        case .high: return 64
        case .medium: return 32
        case .low: return 24
        }
    }

    var displayName: String {
        switch self {
        case .high: return "High (22kHz, 64kbps)"
        case .medium: return "Medium (16kHz, 32kbps)"
        case .low: return "Low (12kHz, 24kbps)"
        }
    }
}
