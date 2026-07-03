import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Caches SCShareableContent, whose window-server fetch takes 0.5–2s+ and sits
/// on the meeting-start critical path. Pre-warmed at app launch, on meeting
/// hotkey intent, and after each meeting stop, so the actual start usually
/// hits a fresh cache.
actor ShareableContentCache {
    static let shared = ShareableContentCache()

    private var content: SCShareableContent?
    private var fetchedAt: Date?
    private var inflight: Task<SCShareableContent, Error>?

    /// Kick off a background refresh; cheap to call often. Fetches only when
    /// screen-recording permission is already granted — an ungranted fetch
    /// would surprise the user with the system permission prompt.
    nonisolated func prewarm() {
        guard CGPreflightScreenCaptureAccess() else { return }
        Task { _ = try? await self.refresh() }
    }

    /// Cached content if fresh enough, else a fresh fetch. Cached content can
    /// reference since-removed displays — callers that build an SCStream from
    /// it must retry once with `refresh()` on stream-start failure.
    func current(maxAge: TimeInterval = 60) async throws -> SCShareableContent {
        if let content, let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge {
            return content
        }
        return try await refresh()
    }

    /// Always fetches fresh and updates the cache. Concurrent callers share
    /// one in-flight fetch.
    func refresh() async throws -> SCShareableContent {
        if let inflight {
            return try await inflight.value
        }
        let task = Task {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
        inflight = task
        defer { inflight = nil }
        let fresh = try await task.value
        content = fresh
        fetchedAt = Date()
        return fresh
    }
}
