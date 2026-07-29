import AVFoundation
@testable import Diduny
import XCTest

/// Tests for `PreConnectAudioBuffer` — the bounded FIFO that holds audio
/// produced while the realtime socket is still connecting, so the first
/// seconds of speech survive the handshake instead of being dropped.
final class PreConnectAudioBufferTests: XCTestCase {
    private func chunk(_ byte: UInt8, count: Int) -> Data {
        Data(repeating: byte, count: count)
    }

    func testDrainsInFIFOOrder() {
        var buffer = PreConnectAudioBuffer(maxBytes: 1000)
        buffer.append(chunk(1, count: 10))
        buffer.append(chunk(2, count: 20))
        buffer.append(chunk(3, count: 30))

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.totalBytes, 60)
        XCTAssertEqual(buffer.removeFirst(), chunk(1, count: 10))
        XCTAssertEqual(buffer.removeFirst(), chunk(2, count: 20))
        XCTAssertEqual(buffer.removeFirst(), chunk(3, count: 30))
        XCTAssertNil(buffer.removeFirst())
        XCTAssertEqual(buffer.totalBytes, 0)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testEvictsOldestBeyondByteCap() {
        var buffer = PreConnectAudioBuffer(maxBytes: 100)
        buffer.append(chunk(1, count: 40))
        buffer.append(chunk(2, count: 40))
        XCTAssertFalse(buffer.didOverflow)

        buffer.append(chunk(3, count: 40)) // 120 > 100 → chunk 1 evicted

        XCTAssertTrue(buffer.didOverflow)
        XCTAssertEqual(buffer.count, 2)
        XCTAssertEqual(buffer.totalBytes, 80)
        XCTAssertEqual(buffer.removeFirst(), chunk(2, count: 40))
        XCTAssertEqual(buffer.removeFirst(), chunk(3, count: 40))
    }

    func testKeepsLatestChunkEvenWhenLargerThanCap() {
        var buffer = PreConnectAudioBuffer(maxBytes: 10)
        buffer.append(chunk(1, count: 50))

        // A single oversized chunk is kept — dropping it would lose the only
        // audio we have; the cap bounds accumulation, not chunk size.
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer.removeFirst(), chunk(1, count: 50))
    }

    func testRemoveAllResetsStateIncludingOverflowFlag() {
        var buffer = PreConnectAudioBuffer(maxBytes: 50)
        buffer.append(chunk(1, count: 40))
        buffer.append(chunk(2, count: 40))
        XCTAssertTrue(buffer.didOverflow)

        buffer.removeAll()

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.totalBytes, 0)
        XCTAssertFalse(buffer.didOverflow)
    }

    func testFifteenSecondsOfRealtimeAudioFitsDefaultCap() {
        // The realtime stream is 16kHz mono s16le = 32,000 bytes/s, delivered
        // in ~100ms chunks. 15s of it must fit without eviction.
        var buffer = PreConnectAudioBuffer()
        let chunkBytes = 3200
        for _ in 0 ..< 150 {
            buffer.append(chunk(7, count: chunkBytes))
        }
        XCTAssertFalse(buffer.didOverflow)
        XCTAssertEqual(buffer.totalBytes, 480_000)
    }

    func testRealtimeSpeechGateKeepsSilenceLocalAndTimesOut() {
        let gate = RealtimeSpeechGate(maxBytes: 640)
        let silence = pcmData(Array(repeating: 0, count: 320))

        XCTAssertTrue(gate.append(silence).isEmpty)
        XCTAssertFalse(gate.consumeNoSpeechTimeout())
        XCTAssertTrue(gate.append(silence).isEmpty)
        XCTAssertTrue(gate.append(silence).isEmpty)
        XCTAssertTrue(gate.consumeNoSpeechTimeout())
        XCTAssertTrue(gate.append(silence).isEmpty)
        XCTAssertFalse(gate.consumeNoSpeechTimeout())
    }

    func testRealtimeSpeechGateReleasesBufferedAudioAfterSpeech() {
        let gate = RealtimeSpeechGate(maxBytes: 20_000)
        let silence = pcmData(Array(repeating: 0, count: 960))
        let speech = pcmData(Array(repeating: 1_000, count: 3_200))

        XCTAssertTrue(gate.append(silence).isEmpty)
        XCTAssertEqual(gate.append(speech), [silence, speech])

        let laterSpeech = pcmData(Array(repeating: 2_000, count: 320))
        XCTAssertEqual(gate.append(laterSpeech), [laterSpeech])
        XCTAssertFalse(gate.consumeNoSpeechTimeout())
    }

    func testRealtimeSpeechGateOpensWhenSpeechStartsImmediately() {
        let gate = RealtimeSpeechGate(maxBytes: 20_000)
        let speech = pcmData(Array(repeating: 1_000, count: 3_200))

        XCTAssertEqual(gate.append(speech), [speech])
    }

    func testSpeechPrecheckFailsClosedWhenAudioCannotBeDecoded() async {
        let hasSpeech = await AudioSpeechDetector.hasSpeech(in: Data())

        XCTAssertFalse(hasSpeech)
    }

    func testSpeechPrecheckAcceptsAudioThatStartsWithSpeech() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSpeechDetectorTests-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
            buffer.frameLength = 16_000
            for index in 0 ..< 16_000 {
                buffer.floatChannelData![0][index] = 0.05 * sin(Float(index) * 2 * .pi * 220 / 16_000)
            }
            try file.write(from: buffer)
        }

        let hasSpeech = await AudioSpeechDetector.hasSpeech(in: try Data(contentsOf: url))
        XCTAssertTrue(hasSpeech)
    }

    private func pcmData(_ samples: [Int16]) -> Data {
        samples.withUnsafeBytes { Data($0) }
    }
}
