import Foundation

/// Ordered output of the coalescer: merged token runs interleaved with
/// segment boundaries, preserving arrival order.
enum CoalescedTranscriptEvent {
    case tokens([RealtimeToken])
    case segmentBoundary(RealtimeSegmentBoundary)
}

/// Coalesces per-WebSocket-message token batches into main-actor flushes at
/// most every `interval` (~10Hz by default). Realtime tokens can arrive many
/// times per second; delivering each batch straight to an @Observable store
/// re-renders SwiftUI per message and lets main-thread cost grow with the
/// session.
///
/// Merging is semantics-aware: final tokens are append-only and accumulate,
/// but non-final tokens are FULL SNAPSHOTS of the provisional tail, re-sent on
/// every message — only the latest batch's snapshot survives a merge.
/// Concatenating snapshots across messages would show duplicated provisional
/// text until the next flush replaced it.
final class RealtimeTokenCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    /// Compacted, ordered events for the next flush. Consecutive token batches
    /// merge into one run; a boundary closes the current run so ordering
    /// relative to tokens is preserved.
    private var events: [CoalescedTranscriptEvent] = []
    private var runFinals: [RealtimeToken] = []
    private var runLatestNonFinals: [RealtimeToken] = []
    private var hasOpenRun = false
    private var flushTask: Task<Void, Never>?
    private let interval: Duration
    private let onFlush: @MainActor ([CoalescedTranscriptEvent]) -> Void

    init(
        interval: Duration = .milliseconds(100),
        onFlush: @escaping @MainActor ([CoalescedTranscriptEvent]) -> Void
    ) {
        self.interval = interval
        self.onFlush = onFlush
    }

    /// Queue a message's token batch; schedules a flush `interval` from now
    /// unless one is already pending. Callable from any thread.
    func add(_ tokens: [RealtimeToken]) {
        guard !tokens.isEmpty else { return }
        lock.lock()
        runFinals.append(contentsOf: tokens.filter(\.isFinal))
        // Snapshot semantics: this message's non-final set REPLACES the
        // previous one (an all-final message legitimately clears it).
        runLatestNonFinals = tokens.filter { !$0.isFinal }
        hasOpenRun = true
        scheduleFlushLocked()
        lock.unlock()
    }

    /// Queue a segment boundary in order relative to token batches.
    func addBoundary(_ boundary: RealtimeSegmentBoundary) {
        lock.lock()
        closeRunLocked()
        events.append(.segmentBoundary(boundary))
        scheduleFlushLocked()
        lock.unlock()
    }

    /// Deliver everything queued right now — used at stop/finalize so the
    /// transcript tail is in the store before it is read.
    func flushNow() async {
        lock.lock()
        flushTask?.cancel()
        flushTask = nil
        lock.unlock()
        await deliverPending()
    }

    private func scheduleFlushLocked() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: interval)
            await self.deliverPending()
        }
    }

    private func closeRunLocked() {
        guard hasOpenRun else { return }
        let run = runFinals + runLatestNonFinals
        if !run.isEmpty {
            events.append(.tokens(run))
        }
        runFinals = []
        runLatestNonFinals = []
        hasOpenRun = false
    }

    private func deliverPending() async {
        lock.lock()
        flushTask = nil
        closeRunLocked()
        let toDeliver = events
        events = []
        lock.unlock()
        guard !toDeliver.isEmpty else { return }
        await onFlush(toDeliver)
    }
}
