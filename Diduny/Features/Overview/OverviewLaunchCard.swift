import AppKit
import AVFAudio
import SwiftUI

struct OverviewLaunchCard: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioDeviceManager.self) private var audioDeviceManager
    @State private var onboarding = OnboardingManager.shared
    @State private var authService = AuthService.shared
    @State private var updateArrival = UpdateArrivalState.shared
    @State private var microphoneGranted = false
    @State private var accessibilityGranted = false
    @State private var microphoneRequestInFlight = false
    @State private var accessibilityRequestInFlight = false
    @State private var shouldEnableAutoPasteAfterGrant = false

    private let releaseHighlights = ReleaseHighlights.bundled()

    var body: some View {
        if onboarding.shouldShowSetupGuide {
            setupGuideCard
        } else if onboarding.canShowUpdateHighlights, let releaseLine = updateArrival.pendingReleaseLine {
            if let releaseHighlights {
                whatsNewCard(releaseLine: releaseLine, highlights: releaseHighlights)
            }
        }
    }

    private var setupGuideCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up Diduny")
                        .font(.title3.bold())
                    Text("Three quick steps to your first dictation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(onboarding.hasCompletedOnboarding ? "Done" : "Set up later") {
                    onboarding.hideSetupGuideForSession()
                }
                .buttonStyle(.borderless)
                .accessibilityHint(
                    onboarding.hasCompletedOnboarding
                        ? "Closes the completed setup guide"
                        : "Collapses the setup guide until Diduny is relaunched"
                )
            }

            setupStep(
                number: 1,
                title: "Sign in for cloud dictation",
                isComplete: authService.isLoggedIn
            ) {
                AccountSignInView()
            }

            Divider()

            setupStep(
                number: 2,
                title: "Allow Microphone",
                isComplete: microphoneGranted
            ) {
                microphoneSetupContent
            }

            Divider()

            setupStep(
                number: 3,
                title: "Try a short dictation",
                isComplete: onboarding.hasCompletedOnboarding
            ) {
                practiceContent
            }

            Divider()

            accessibilitySetupRow
        }
        .padding(20)
        .background(Color(.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set up Diduny")
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await refreshSetupState() }
        }
        .task {
            await refreshSetupState()
        }
    }

    private func setupStep(
        number: Int,
        title: String,
        isComplete: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : Color.secondary.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: isComplete ? "checkmark" : "\(number).circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(isComplete ? Color.white : Color.secondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var microphoneSetupContent: some View {
        if microphoneGranted {
            Label("Microphone access allowed", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if AVAudioApplication.shared.recordPermission == .denied {
            Text("Microphone access is off. Enable Diduny in Privacy & Security > Microphone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open System Settings") {
                PermissionManager.shared.openSystemSettingsForPermission(.microphone)
            }
            .accessibilityHint("Opens the Microphone privacy pane")
        } else {
            Button("Allow Microphone") {
                requestMicrophonePermission()
            }
            .disabled(microphoneRequestInFlight)
        }

        if audioDeviceManager.availableDevices.isEmpty {
            Text("No microphone found. Connect one, then refresh.")
                .font(.subheadline)
                .foregroundStyle(.red)
            Button("Refresh Microphones") {
                audioDeviceManager.refreshDevices()
            }
        }
    }

    private var practiceContent: some View {
        let canPractice = onboarding.canStartPractice(
            isAuthenticated: authService.isLoggedIn,
            microphoneGranted: microphoneGranted
        ) && !audioDeviceManager.availableDevices.isEmpty
        let isRecording = appState.recordingState == .recording
        let isProcessing = appState.recordingState == .processing
        let status = practiceStatus

        return VStack(alignment: .leading, spacing: 8) {
            Text("Hold Right Shift, speak, then release.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(status.text, systemImage: status.symbol)
                .font(.subheadline)
                .foregroundStyle(status.color)
                .accessibilityLabel(status.text)

            Button(isRecording ? "Stop and transcribe" : "Start practice") {
                MainWindowController.shared.toggleRecording()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPractice || isProcessing)
            .accessibilityHint(
                isRecording
                    ? "Stops the current dictation and transcribes it"
                    : "Starts a cloud dictation without using the keyboard shortcut"
            )
        }
    }

    private var practiceStatus: PracticeStatus {
        switch appState.recordingState {
        case .idle:
            let text = if !authService.isLoggedIn {
                "Sign in to continue"
            } else if !microphoneGranted {
                "Allow Microphone to continue"
            } else if audioDeviceManager.availableDevices.isEmpty {
                "Connect a microphone to continue"
            } else {
                "Ready"
            }
            return PracticeStatus(text: text, symbol: "circle", color: .secondary)
        case .recording:
            return PracticeStatus(text: "Listening…", symbol: "waveform", color: .secondary)
        case .processing:
            return PracticeStatus(text: "Transcribing…", symbol: "ellipsis.circle", color: .secondary)
        case .success:
            return PracticeStatus(
                text: "Saved to Recordings and copied to the clipboard",
                symbol: "checkmark.circle.fill",
                color: .green
            )
        case .error:
            return PracticeStatus(
                text: appState.errorMessage ?? "Dictation failed. Try again.",
                symbol: "exclamationmark.triangle.fill",
                color: .red
            )
        }
    }

    private struct PracticeStatus {
        let text: String
        let symbol: String
        let color: Color
    }

    private var accessibilitySetupRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "cursorarrow.click")
                .frame(width: 24, height: 24)
                .foregroundStyle(accessibilityGranted ? Color.green : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-paste (optional)")
                    .font(.headline)
                Text("Without this permission, Diduny copies completed text. Paste it with ⌘V.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if accessibilityGranted {
                    Text(
                        SettingsStorage.shared.autoPaste
                            ? "Auto-paste is enabled."
                            : "Accessibility access is allowed."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Button("Enable Auto-paste") {
                        requestAccessibilityPermission()
                    }
                    .disabled(accessibilityRequestInFlight)
                }
            }
        }
    }

    private func whatsNewCard(releaseLine: String, highlights: ReleaseHighlights) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color("BrandAccentDeep"))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("What’s New in Diduny \(releaseLine)")
                    .font(.title3.bold())
                Text(highlights.headline)
                    .font(.headline)
                ForEach(Array(highlights.highlights.enumerated()), id: \.offset) { _, highlight in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .accessibilityHidden(true)
                        Text(highlight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                updateArrival.dismissPendingRelease()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss What’s New for Diduny \(releaseLine)")
        }
        .padding(20)
        .background(Color("BrandTintSoft"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("BrandTintBorder"), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func requestMicrophonePermission() {
        microphoneRequestInFlight = true
        Task {
            _ = await PermissionManager.shared.requestMicrophonePermission()
            await refreshSetupState()
            microphoneRequestInFlight = false
        }
    }

    private func requestAccessibilityPermission() {
        accessibilityRequestInFlight = true
        shouldEnableAutoPasteAfterGrant = true
        PermissionManager.shared.requestAccessibilityPermission()
        Task {
            try? await Task.sleep(for: .seconds(1))
            await refreshSetupState()
            accessibilityRequestInFlight = false
        }
    }

    private func refreshSetupState() async {
        await PermissionManager.shared.refreshStatus()
        microphoneGranted = PermissionManager.shared.status.microphone
        accessibilityGranted = PermissionManager.shared.status.accessibility
        audioDeviceManager.refreshDevices()

        if shouldEnableAutoPasteAfterGrant, accessibilityGranted {
            SettingsStorage.shared.autoPaste = true
            shouldEnableAutoPasteAfterGrant = false
        }
    }
}
