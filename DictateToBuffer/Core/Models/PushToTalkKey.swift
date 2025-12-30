import Foundation

enum PushToTalkKey: String, Codable, CaseIterable {
    case none
    case capsLock
    case rightShift
    case rightOption

    var displayName: String {
        switch self {
        case .none:
            return "Disabled"
        case .capsLock:
            return "Caps Lock"
        case .rightShift:
            return "Right Shift"
        case .rightOption:
            return "Right Option"
        }
    }

    var symbol: String {
        switch self {
        case .none:
            return ""
        case .capsLock:
            return "⇪"
        case .rightShift:
            return "⇧"
        case .rightOption:
            return "⌥"
        }
    }
}
