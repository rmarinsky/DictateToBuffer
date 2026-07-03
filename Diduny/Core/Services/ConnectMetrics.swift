import Foundation
import os

/// Collects phase timings for one realtime connect (or meeting start) and emits
/// them as os_signpost intervals plus a single summary log line, so connect
/// latency can be measured from Console / `log stream` or Instruments and
/// compared before/after optimizations.
///
/// Thread-safe: phases may begin/end on different threads (e.g. `upgrade`
/// ends on the URLSession delegate queue while `config` runs on the caller).
final class ConnectMetrics: @unchecked Sendable {
    enum Phase: String {
        case tokenFetch = "token"
        case wsUpgrade = "upgrade"
        case configSend = "config"
        case proxyReadyWait = "ready"
        case recorderStart = "recorder"
    }

    private static let signposter = OSSignposter(
        subsystem: "ua.com.rmarinsky.diduny",
        category: "connect"
    )

    private let label: String
    private let lock = NSLock()
    private let signpostID: OSSignpostID
    private let totalState: OSSignpostIntervalState
    private let startedAt = ContinuousClock.now
    private var openPhases: [Phase: (state: OSSignpostIntervalState, start: ContinuousClock.Instant)] = [:]
    private var completedPhases: [(phase: Phase, ms: Int)] = []
    private var summaryEmitted = false

    init(label: String) {
        self.label = label
        signpostID = Self.signposter.makeSignpostID()
        totalState = Self.signposter.beginInterval("total", id: signpostID, "\(label)")
    }

    func begin(_ phase: Phase) {
        let state = Self.signposter.beginInterval("phase", id: signpostID, "\(self.label).\(phase.rawValue)")
        lock.lock()
        openPhases[phase] = (state, .now)
        lock.unlock()
    }

    func end(_ phase: Phase) {
        lock.lock()
        guard let entry = openPhases.removeValue(forKey: phase) else {
            lock.unlock()
            return
        }
        completedPhases.append((phase, Self.milliseconds(since: entry.start)))
        lock.unlock()
        Self.signposter.endInterval("phase", entry.state)
    }

    /// Ends the total interval and logs one summary line. Idempotent, so error
    /// paths can rely on a `defer { metrics.finish(outcome: "aborted") }` while
    /// the success path calls `finish(outcome: "ok")` explicitly first.
    func finish(outcome: String = "aborted") {
        lock.lock()
        guard !summaryEmitted else {
            lock.unlock()
            return
        }
        summaryEmitted = true
        // Close phases left open by an error path so their time is still reported.
        let abandoned = openPhases
        openPhases.removeAll()
        for (phase, entry) in abandoned {
            completedPhases.append((phase, Self.milliseconds(since: entry.start)))
        }
        let phases = completedPhases
            .map { "\($0.phase.rawValue)=\($0.ms)ms" }
            .joined(separator: " ")
        lock.unlock()

        for (_, entry) in abandoned {
            Self.signposter.endInterval("phase", entry.state)
        }
        Self.signposter.endInterval("total", totalState)

        let totalMs = Self.milliseconds(since: startedAt)
        NSLog("%@", "\(label) timings: \(phases) total=\(totalMs)ms outcome=\(outcome)")
    }

    /// One-shot interval around an async operation, for call sites that don't
    /// carry a ConnectMetrics instance (e.g. deep inside capture services).
    static func measure<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("measure", id: signpostID, "\(label)")
        let start = ContinuousClock.now
        defer {
            signposter.endInterval("measure", state)
            NSLog("%@", "\(label) took \(milliseconds(since: start))ms")
        }
        return try await body()
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        return Int(duration.components.seconds) * 1000
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
