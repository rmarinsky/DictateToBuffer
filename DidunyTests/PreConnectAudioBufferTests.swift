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
}
