import Foundation
import Observation

@MainActor
@Observable
final class UpdateArrivalState {
    static let shared = UpdateArrivalState()

    static let highestLaunchedVersionKey = "updates.highestLaunchedVersion"
    static let pendingReleaseLineKey = "updates.pendingReleaseLine"

    private let defaults: UserDefaults
    private(set) var pendingReleaseLine: String?

    var highestLaunchedVersion: String? {
        defaults.string(forKey: Self.highestLaunchedVersionKey)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pendingReleaseLine = defaults.string(forKey: Self.pendingReleaseLineKey)
    }

    func recordLaunch(version: String, isFreshInstall: Bool) {
        guard let current = Version(version) else {
            NSLog("[Updates] Ignoring invalid launched version: %@", version)
            return
        }
        guard let highestRaw = highestLaunchedVersion else {
            defaults.set(current.description, forKey: Self.highestLaunchedVersionKey)
            if !isFreshInstall { setPendingReleaseLine(current.releaseLine) }
            return
        }
        guard let highest = Version(highestRaw), highest < current else { return }

        defaults.set(current.description, forKey: Self.highestLaunchedVersionKey)
        if highest.releaseLine != current.releaseLine {
            setPendingReleaseLine(current.releaseLine)
        }
    }

    func dismissPendingRelease() {
        pendingReleaseLine = nil
        defaults.removeObject(forKey: Self.pendingReleaseLineKey)
    }

    private func setPendingReleaseLine(_ line: String) {
        pendingReleaseLine = line
        defaults.set(line, forKey: Self.pendingReleaseLineKey)
    }

    private struct Version: Comparable, CustomStringConvertible {
        let major: Int
        let minor: Int
        let patch: Int

        init?(_ rawValue: String) {
            let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
            guard components.count == 3,
                  let major = Int(components[0]),
                  let minor = Int(components[1]),
                  let patch = Int(components[2]),
                  major >= 0, minor >= 0, patch >= 0 else { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        var releaseLine: String { "\(major).\(minor)" }
        var description: String { "\(releaseLine).\(patch)" }

        static func < (lhs: Version, rhs: Version) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }
}
