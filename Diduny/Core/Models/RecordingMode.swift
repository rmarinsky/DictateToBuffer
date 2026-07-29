enum RecordingMode: Equatable {
    case voice
    case translation(targetLanguage: String = "EN <-> UK")
    case meeting
    case meetingTranslation
    case fileTranscription

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
