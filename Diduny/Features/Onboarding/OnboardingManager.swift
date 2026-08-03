import Foundation
import Observation

/// Persisted raw values are append-only. Existing installations may still store
/// the deprecated apiSetup value.
enum OnboardingStep: Int, Codable, CaseIterable {
    case welcome = 0
    case microphonePermission = 1
    case accessibilityPermission = 2
    case screenRecordingPermission = 3
    case shortcutSetup = 4
    case apiSetup = 5
    case complete = 6

    var displayName: String {
        switch self {
        case .welcome: "Welcome"
        case .microphonePermission: "Microphone"
        case .accessibilityPermission: "Accessibility"
        case .screenRecordingPermission: "Screen Recording"
        case .shortcutSetup: "Shortcut Setup"
        case .apiSetup: "API Setup"
        case .complete: "Complete"
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

@Observable
final class OnboardingManager {
    static let shared = OnboardingManager()

    private static let completedKey = "onboarding.completed"
    private static let versionKey = "onboarding.version"
    private static let currentStepKey = "onboarding.currentStep"
    private static let firstLaunchTimestampKey = "onboarding.firstLaunchTimestamp"
    private static let stepCompletedPrefix = "onboarding.step."
    private static let currentVersion = 1

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let applyNewUserDefaults: () -> Void

    private(set) var setupGuideHiddenForSession = false

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
        !hasCompletedOnboarding && !setupGuideHiddenForSession
    }

    /// Applies first-install defaults before runtime services snapshot them.
    /// Returns true only on the first launch of a new installation.
    @discardableResult
    func prepareForLaunch() -> Bool {
        let freshInstall = isFirstLaunch
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
    }

    func showSetupGuide() {
        setupGuideHiddenForSession = false
    }

    func showFromSettings() {
        showSetupGuide()
    }

    func canStartPractice(isAuthenticated: Bool, microphoneGranted: Bool) -> Bool {
        isAuthenticated && microphoneGranted
    }

    /// Called only after RecordingsLibraryStorage confirms a saved recording.
    @discardableResult
    func didSaveSuccessfulDictation(
        recordingID: UUID?,
        text: String,
        provider: TranscriptionProvider,
        isAuthenticated: Bool
    ) -> Bool {
        guard recordingID != nil,
              !hasCompletedOnboarding,
              provider == .cloud,
              isAuthenticated,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        hasCompletedOnboarding = true
        return true
    }

    /// Legacy persistence accessor retained for migrations and tests.
    func completeStep(_ step: OnboardingStep) {
        defaults.set(true, forKey: Self.stepCompletedPrefix + "\(step.rawValue)")
        if let next = step.next {
            currentStep = next
        }
    }

    func isStepCompleted(_ step: OnboardingStep) -> Bool {
        defaults.bool(forKey: Self.stepCompletedPrefix + "\(step.rawValue)")
    }

    func skipToStep(_ step: OnboardingStep) {
        currentStep = step
    }

    func setupDefaultsForNewUser() {
        guard isFirstLaunch else { return }
        applyNewUserDefaults()
    }

    func reset() {
        defaults.removeObject(forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.versionKey)
        defaults.removeObject(forKey: Self.currentStepKey)
        defaults.removeObject(forKey: Self.firstLaunchTimestampKey)
        for step in OnboardingStep.allCases {
            defaults.removeObject(forKey: Self.stepCompletedPrefix + "\(step.rawValue)")
        }
        setupGuideHiddenForSession = false
    }
}
