import os

enum Log {
    static let app = Logger(subsystem: "com.dictate.buffer", category: "app")
    static let recording = Logger(subsystem: "com.dictate.buffer", category: "recording")
    static let transcription = Logger(subsystem: "com.dictate.buffer", category: "transcription")
    static let audio = Logger(subsystem: "com.dictate.buffer", category: "audio")
    static let permissions = Logger(subsystem: "com.dictate.buffer", category: "permissions")
}
