import Foundation

/// Coalesces per-WebSocket-message token batches into main-actor flushes at
/// most every `interval` (~10Hz by default). Realtime tokens can arrive many
/// times per second; delivering each batch straight to an @Observable store
/// re-renders SwiftUI per message and lets main-thread cost grow with the
/// session. Batching preserves token order and caps UI work at a fixed rate.
final class RealtimeTokenCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [RealtimeToken] = []
    private var flushTask: Task<Void, Never>?
    private let interval: Duration
    private let onFlush: @MainActor ([RealtimeToken]) -> Void

    init(
        interval: Duration = .milliseconds(100),
        onFlush: @escaping @MainActor ([RealtimeToken]) -> Void
    ) {
        self.interval = interval
        self.onFlush = onFlush
    }

    /// Queue a batch; schedules a flush `interval` from now unless one is
    /// already pending. Callable from any thread.
    func add(_ tokens: [RealtimeToken]) {
        guard !tokens.isEmpty else { return }
        lock.lock()
        pending.append(contentsOf: tokens)
        if flushTask == nil {
            flushTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: interval)
                await self.deliverPending()
            }
        }
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

    private func deliverPending() async {
        lock.lock()
        flushTask = nil
        let tokens = pending
        pending = []
        lock.unlock()
        guard !tokens.isEmpty else { return }
        await onFlush(tokens)
    }
}
