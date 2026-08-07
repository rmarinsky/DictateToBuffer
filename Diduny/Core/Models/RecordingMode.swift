enum RecordingMode: Equatable {
    case voice
    case translation(targetLanguage: String = "EN <-> UK")
    case meeting
    case meetingTranslation
    case fileTranscription

    var label: String {
        switch self {
        case .voice: "Recording..."
        case let .translation(targetLanguage): "Recording -> \(targetLanguage)..."
        case .meeting: "Meeting Recording..."
        case .meetingTranslation: "Meeting Translation..."
        case .fileTranscription: "Transcribing File..."
        }
    }

    var processingLabel: String {
        switch self {
        case .voice: "Processing..."
        case .translation: "Translating..."
        case .meeting: "Processing Meeting..."
        case .meetingTranslation: "Translating Meeting..."
        case .fileTranscription: "Transcribing File..."
        }
    }

    var icon: String {
        switch self {
        case .voice: "mic.fill"
        case .translation: "globe"
        case .meeting: "laptopcomputer"
        case .meetingTranslation: "captions.bubble.fill"
        case .fileTranscription: "doc.richtext.fill"
        }
    }

    var isMeeting: Bool {
        switch self {
        case .meeting, .meetingTranslation: true
        case .voice, .translation, .fileTranscription: false
        }
    }
}
