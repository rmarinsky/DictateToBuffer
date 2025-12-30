import Foundation
import Combine

enum RecordingState: Equatable, CustomStringConvertible {
    case idle
    case recording
    case processing
    case success
    case error

    var description: String {
        switch self {
        case .idle: return "idle"
        case .recording: return "recording"
        case .processing: return "processing"
        case .success: return "success"
        case .error: return "error"
        }
    }
}

enum MeetingRecordingState: Equatable, CustomStringConvertible {
    case idle
    case recording
    case processing
    case success
    case error

    var description: String {
        switch self {
        case .idle: return "idle"
        case .recording: return "recording"
        case .processing: return "processing"
        case .success: return "success"
        case .error: return "error"
        }
    }
}

final class AppState: ObservableObject {
    @Published var recordingState: RecordingState = .idle {
        didSet {
            NSLog("[AppState] recordingState changed: \(oldValue) -> \(recordingState)")
        }
    }
    @Published var recordingStartTime: Date?
    @Published var lastTranscription: String?
    @Published var errorMessage: String? {
        didSet {
            if let msg = errorMessage {
                NSLog("[AppState] errorMessage set: \(msg)")
            }
        }
    }

    @Published var useAutoDetect: Bool
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var microphonePermissionGranted: Bool = false
    @Published var screenCapturePermissionGranted: Bool = false

    // Meeting recording
    @Published var meetingRecordingState: MeetingRecordingState = .idle {
        didSet {
            NSLog("[AppState] meetingRecordingState changed: \(oldValue) -> \(meetingRecordingState)")
        }
    }
    @Published var meetingRecordingStartTime: Date?

    var recordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    var meetingRecordingDuration: TimeInterval {
        guard let startTime = meetingRecordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    init() {
        let settings = SettingsStorage.shared
        self.useAutoDetect = settings.useAutoDetect
        self.selectedDeviceID = settings.selectedDeviceID
        NSLog("[AppState] Initialized: useAutoDetect=\(useAutoDetect), selectedDeviceID=\(String(describing: selectedDeviceID))")
    }
}
