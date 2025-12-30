import Foundation

enum MeetingAudioSource: String, Codable, CaseIterable {
    case systemOnly
    case systemPlusMicrophone

    var displayName: String {
        switch self {
        case .systemOnly:
            return "System Audio Only"
        case .systemPlusMicrophone:
            return "System + Microphone"
        }
    }

    var description: String {
        switch self {
        case .systemOnly:
            return "Record only what you hear (meeting participants)"
        case .systemPlusMicrophone:
            return "Record yourself and meeting participants"
        }
    }
}
