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
