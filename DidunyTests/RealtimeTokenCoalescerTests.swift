@testable import Diduny
import XCTest

/// Tests for `RealtimeTokenCoalescer` — per-message token batches must arrive
/// merged, in order, at a bounded rate, and `flushNow()` must deliver the tail
/// synchronously enough for stop paths to read a complete transcript.
final class RealtimeTokenCoalescerTests: XCTestCase {
    private func token(_ text: String) -> RealtimeToken {
        RealtimeToken(text: text, isFinal: true)
    }

    func testCoalescesManyBatchesIntoFewFlushesPreservingOrder() async throws {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .milliseconds(50)) { tokens in
            collected.record(tokens)
        }

        for i in 0 ..< 20 {
            coalescer.add([token("t\(i)")])
        }
        try await Task.sleep(for: .milliseconds(200))

        let flushes = collected.flushes()
        XCTAssertLessThan(flushes.count, 20, "batches must be merged, not delivered per message")
        XCTAssertEqual(
            flushes.flatMap { $0.map(\.text) },
            (0 ..< 20).map { "t\($0)" },
            "token order must be preserved across coalesced flushes"
        )
    }

    func testFlushNowDeliversPendingImmediately() async {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .seconds(10)) { tokens in
            collected.record(tokens)
        }

        coalescer.add([token("tail")])
        await coalescer.flushNow()

        XCTAssertEqual(collected.flushes().flatMap { $0.map(\.text) }, ["tail"])
    }

    func testEmptyAddDoesNotScheduleFlush() async throws {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .milliseconds(20)) { tokens in
            collected.record(tokens)
        }

        coalescer.add([])
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(collected.flushes().isEmpty)
    }
}

/// Thread-safe flush recorder (flushes land on the main actor).
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[RealtimeToken]] = []

    func record(_ tokens: [RealtimeToken]) {
        lock.lock()
        recorded.append(tokens)
        lock.unlock()
    }

    func flushes() -> [[RealtimeToken]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
