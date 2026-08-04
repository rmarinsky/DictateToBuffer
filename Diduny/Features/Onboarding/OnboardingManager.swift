import Foundation
import Observation

/// Persisted raw values are append-only. Existing installations may still store
/// the deprecated apiSetup value.
enum OnboardingStep: Int, Codable {
    case welcome = 0
    case microphonePermission = 1
    case accessibilityPermission = 2
    case screenRecordingPermission = 3
    case shortcutSetup = 4
    case apiSetup = 5
    case complete = 6
}

@Observable
final class OnboardingManager {
    static let shared = OnboardingManager()

    private static let completedKey = "onboarding.completed"
    private static let versionKey = "onboarding.version"
    private static let currentStepKey = "onboarding.currentStep"
    private static let firstLaunchTimestampKey = "onboarding.firstLaunchTimestamp"
    private static let currentVersion = 1

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let applyNewUserDefaults: () -> Void

    private(set) var setupGuideHiddenForSession = false
    private(set) var setupGuideRequestedForSession = false
    private(set) var didCompleteSetupThisSession = false

    init(
        defaults: UserDefaults = .standard,
        applyNewUserDefaults: @escaping () -> Void = {
            SettingsStorage.shared.applyNewUserDefaultsIfMissing()
        }
    ) {
        self.defaults = defaults
        self.applyNewUserDefaults = applyNewUserDefaults
    }

    var currentStep: OnboardingStep {
        get {
            let rawValue = defaults.integer(forKey: Self.currentStepKey)
            return OnboardingStep(rawValue: rawValue) ?? .welcome
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.currentStepKey)
        }
    }

    var hasCompletedOnboarding: Bool {
        get {
            defaults.bool(forKey: Self.completedKey)
                && defaults.integer(forKey: Self.versionKey) >= Self.currentVersion
        }
        set {
            defaults.set(newValue, forKey: Self.completedKey)
            if newValue {
                defaults.set(Self.currentVersion, forKey: Self.versionKey)
                currentStep = .complete
            }
        }
    }

    var isFirstLaunch: Bool {
        defaults.object(forKey: Self.firstLaunchTimestampKey) == nil
            && defaults.object(forKey: Self.completedKey) == nil
            && defaults.object(forKey: Self.versionKey) == nil
            && defaults.object(forKey: Self.currentStepKey) == nil
    }

    var shouldShowSetupGuide: Bool {
        setupGuideRequestedForSession
            || didCompleteSetupThisSession
            || (!hasCompletedOnboarding && !setupGuideHiddenForSession)
    }

    var shouldPresentOnboardingWindow: Bool {
        shouldShowSetupGuide
    }

    var canShowUpdateHighlights: Bool {
        hasCompletedOnboarding && !shouldShowSetupGuide
    }

    /// Applies first-install defaults before runtime services snapshot them.
    /// Returns true only on the first launch of a new installation.
    @discardableResult
    func prepareForLaunch(hasExistingInstallState: Bool = false) -> Bool {
        let freshInstall = isFirstLaunch && !hasExistingInstallState
        if freshInstall {
            applyNewUserDefaults()
        }
        if defaults.object(forKey: Self.firstLaunchTimestampKey) == nil {
            defaults.set(
                Date().timeIntervalSinceReferenceDate,
                forKey: Self.firstLaunchTimestampKey
            )
        }
        return freshInstall
    }

    func hideSetupGuideForSession() {
        setupGuideHiddenForSession = true
        setupGuideRequestedForSession = false
        didCompleteSetupThisSession = false
    }

    func showSetupGuide() {
        setupGuideHiddenForSession = false
    }

    func showFromSettings() {
        showSetupGuide()
        setupGuideRequestedForSession = true
    }

    func canStartPractice(
        isAuthenticated: Bool,
        microphoneGranted: Bool,
        accessibilityGranted: Bool,
        screenRecordingGranted: Bool
    ) -> Bool {
        isAuthenticated && microphoneGranted && accessibilityGranted && screenRecordingGranted
    }

    func shouldShowReadyAfterPractice(recordingState: RecordingState) -> Bool {
        recordingState == .success && hasCompletedOnboarding
    }

    func dictationProvider(
        configuredProvider: TranscriptionProvider,
        isAuthenticated: Bool
    ) -> TranscriptionProvider {
        !hasCompletedOnboarding && isAuthenticated ? .cloud : configuredProvider
    }

    /// Called only after RecordingsLibraryStorage confirms a saved recording.
    @discardableResult
    func didSaveSuccessfulDictation(
        recordingID: UUID?,
        text: String,
        provider: TranscriptionProvider,
        isAuthenticated: Bool,
        requiredPermissionsGranted: Bool
    ) -> Bool {
        guard recordingID != nil,
              !hasCompletedOnboarding,
              provider == .cloud,
              isAuthenticated,
              requiredPermissionsGranted,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        hasCompletedOnboarding = true
        didCompleteSetupThisSession = true
        return true
    }
}
