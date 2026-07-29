import Foundation

/// Bounded FIFO for audio produced while the realtime socket is still
/// connecting (or reconnecting). Once the cap is exceeded the oldest chunks
/// are evicted, so a stalled connection costs the oldest audio, never
/// unbounded memory. Not thread-safe — callers synchronize externally
/// (CloudRealtimeService guards it with lifecycleLock).
struct PreConnectAudioBuffer {
    /// ~15s of 16kHz mono s16le — enough to cover connect plus one
    /// reconnect backoff without losing speech.
    static let defaultMaxBytes = 480_000

    private(set) var totalBytes = 0
    private(set) var didOverflow = false
    private var chunks: [Data] = []
    let maxBytes: Int

    init(maxBytes: Int = PreConnectAudioBuffer.defaultMaxBytes) {
        self.maxBytes = maxBytes
    }

    var isEmpty: Bool { chunks.isEmpty }
    var count: Int { chunks.count }

    var data: Data {
        chunks.reduce(into: Data()) { $0.append($1) }
    }

    mutating func append(_ data: Data) {
        chunks.append(data)
        totalBytes += data.count
        while totalBytes > maxBytes, chunks.count > 1 {
            totalBytes -= chunks.removeFirst().count
            didOverflow = true
        }
    }

    mutating func removeFirst() -> Data? {
        guard !chunks.isEmpty else { return nil }
        let chunk = chunks.removeFirst()
        totalBytes -= chunk.count
        return chunk
    }

    mutating func removeAll() {
        chunks.removeAll()
        totalBytes = 0
        didOverflow = false
    }
}

/// Keeps realtime PCM local until speech is present. The buffer cap doubles as
/// the no-speech timeout: 480 KB is 15 seconds of 16 kHz mono s16le audio.
final class RealtimeSpeechGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingAudio: PreConnectAudioBuffer
    private var isOpen = false
    private var noSpeechTimeoutPending = false
    private var didReportNoSpeechTimeout = false

    init(maxBytes: Int = PreConnectAudioBuffer.defaultMaxBytes) {
        pendingAudio = PreConnectAudioBuffer(maxBytes: maxBytes)
    }

    func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }

        return lock.withLock {
            if isOpen { return [data] }

            pendingAudio.append(data)
            if AudioSpeechDetector.hasSpeech(inPCM16: pendingAudio.data) {
                isOpen = true
                var released: [Data] = []
                while let chunk = pendingAudio.removeFirst() {
                    released.append(chunk)
                }
                return released
            }

            if pendingAudio.didOverflow, !didReportNoSpeechTimeout {
                noSpeechTimeoutPending = true
                didReportNoSpeechTimeout = true
            }
            return []
        }
    }

    func consumeNoSpeechTimeout() -> Bool {
        lock.withLock {
            let value = noSpeechTimeoutPending
            noSpeechTimeoutPending = false
            return value
        }
    }
}
