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
        guard highestLaunchedVersion == nil else { return }
        defaults.set(version, forKey: Self.highestLaunchedVersionKey)
        guard !isFreshInstall, let line = Self.releaseLine(for: version) else { return }
        pendingReleaseLine = line
        defaults.set(line, forKey: Self.pendingReleaseLineKey)
    }

    func dismissPendingRelease() {
        pendingReleaseLine = nil
        defaults.removeObject(forKey: Self.pendingReleaseLineKey)
    }

    private static func releaseLine(for version: String) -> String? {
        let components = version.split(separator: ".")
        guard components.count == 3,
              components.allSatisfy({ Int($0) != nil }) else { return nil }
        return "\(components[0]).\(components[1])"
    }
}
