@testable import Diduny
import XCTest

/// Tests for `RealtimeTokenCoalescer` — per-message token batches must arrive
/// merged with snapshot semantics (finals accumulate, only the latest
/// non-final snapshot survives), in order, at a bounded rate, and `flushNow()`
/// must deliver the tail synchronously enough for stop paths to read a
/// complete transcript.
final class RealtimeTokenCoalescerTests: XCTestCase {
    private func token(_ text: String, isFinal: Bool = true) -> RealtimeToken {
        RealtimeToken(text: text, isFinal: isFinal)
    }

    private func tokenTexts(_ events: [[CoalescedTranscriptEvent]]) -> [String] {
        events.flatMap { flush in
            flush.flatMap { event -> [String] in
                if case let .tokens(tokens) = event {
                    return tokens.map(\.text)
                }
                return []
            }
        }
    }

    func testCoalescesManyBatchesIntoFewFlushesPreservingFinalOrder() async throws {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .milliseconds(50)) { events in
            collected.record(events)
        }

        for i in 0 ..< 20 {
            coalescer.add([token("t\(i)")])
        }
        try await Task.sleep(for: .milliseconds(200))

        let flushes = collected.flushes()
        XCTAssertLessThan(flushes.count, 20, "batches must be merged, not delivered per message")
        XCTAssertEqual(
            tokenTexts(flushes),
            (0 ..< 20).map { "t\($0)" },
            "final token order must be preserved across coalesced flushes"
        )
    }

    /// Regression: non-final tokens are full snapshots of the provisional tail,
    /// re-sent on every message. Merging messages by concatenation showed the
    /// previous snapshot alongside the new one (stale text that then got
    /// replaced). Only the LATEST snapshot may survive a merge.
    func testMergeKeepsOnlyLatestNonFinalSnapshot() async {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .seconds(10)) { events in
            collected.record(events)
        }

        coalescer.add([token("hello wor", isFinal: false)])
        coalescer.add([token("hello world", isFinal: false)])
        coalescer.add([token("hello ", isFinal: true), token("world, hi", isFinal: false)])
        await coalescer.flushNow()

        XCTAssertEqual(
            tokenTexts(collected.flushes()),
            ["hello ", "world, hi"],
            "merged flush must carry accumulated finals + only the latest provisional snapshot"
        )
    }

    /// An all-final message clears the provisional tail; a merged flush must
    /// preserve that (finals present, no non-finals) so consumers reset
    /// provisional text.
    func testAllFinalMessageClearsSnapshotInMergedFlush() async {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .seconds(10)) { events in
            collected.record(events)
        }

        coalescer.add([token("provisional", isFinal: false)])
        coalescer.add([token("final.", isFinal: true)])
        await coalescer.flushNow()

        let flushes = collected.flushes()
        XCTAssertEqual(tokenTexts(flushes), ["final."])
    }

    func testBoundaryStaysOrderedRelativeToTokenRuns() async {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .seconds(10)) { events in
            collected.record(events)
        }

        coalescer.add([token("before")])
        coalescer.addBoundary(.endpoint)
        coalescer.add([token("after")])
        await coalescer.flushNow()

        let flush = collected.flushes().first ?? []
        XCTAssertEqual(flush.count, 3)
        guard flush.count == 3,
              case let .tokens(first) = flush[0],
              case .segmentBoundary = flush[1],
              case let .tokens(last) = flush[2]
        else {
            return XCTFail("expected tokens / boundary / tokens, got \(flush)")
        }
        XCTAssertEqual(first.map(\.text), ["before"])
        XCTAssertEqual(last.map(\.text), ["after"])
    }

    func testFlushNowDeliversPendingImmediately() async {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .seconds(10)) { events in
            collected.record(events)
        }

        coalescer.add([token("tail")])
        await coalescer.flushNow()

        XCTAssertEqual(tokenTexts(collected.flushes()), ["tail"])
    }

    func testEmptyAddDoesNotScheduleFlush() async throws {
        let collected = Collector()
        let coalescer = RealtimeTokenCoalescer(interval: .milliseconds(20)) { events in
            collected.record(events)
        }

        coalescer.add([])
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertTrue(collected.flushes().isEmpty)
    }
}

/// Thread-safe flush recorder (flushes land on the main actor).
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[CoalescedTranscriptEvent]] = []

    func record(_ events: [CoalescedTranscriptEvent]) {
        lock.lock()
        recorded.append(events)
        lock.unlock()
    }

    func flushes() -> [[CoalescedTranscriptEvent]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
