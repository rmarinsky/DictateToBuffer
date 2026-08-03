import SwiftUI

struct AccountSignInView: View {
    @State private var email = ""
    @State private var otpCode = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let authService: AuthService

    @MainActor
    init() {
        authService = .shared
    }

    @MainActor
    init(authService: AuthService) {
        self.authService = authService
    }

    var body: some View {
        switch authService.authState {
        case .loggedOut:
            if authService.showsMigrationNotice {
                Label(
                    "Diduny's account system changed. Sign in again to continue using Cloud features.",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            HStack {
                TextField("Your email address", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .accessibilityLabel("Email address")

                Button("Send Code", action: sendOtp)
                    .buttonStyle(.bordered)
                    .disabled(email.isEmpty || isLoading)
            }

        case .otpSent:
            HStack {
                TextField("Enter 6-digit code", text: $otpCode)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .accessibilityLabel("One-time code")

                Button("Verify", action: verifyOtp)
                    .buttonStyle(.borderedProminent)
                    .disabled(otpCode.isEmpty || isLoading)

                Button("Cancel", action: cancelOtp)
                    .buttonStyle(.bordered)
            }

        case .loggedIn:
            HStack {
                Text(authService.userEmail.map { "Logged in as \($0)" } ?? "Logged in")
                    .foregroundColor(.secondary)

                Spacer()

                Button("Sign Out") {
                    Task { await authService.logout() }
                }
                .buttonStyle(.bordered)
            }

            Label("Credentials are stored in the macOS Keychain.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if isLoading {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Signing in")
        }

        if let errorMessage {
            VStack(alignment: .leading, spacing: 4) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)

                if authService.authState == .otpSent {
                    Button("Send new code", action: resendOtp)
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                }
            }
        }
    }

    private func sendOtp() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.sendOtp(email: email)
            } catch {
                errorMessage = "Couldn't send a code. Try again."
            }
            isLoading = false
        }
    }

    private func verifyOtp() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.verifyOtp(email: email, code: otpCode)
                otpCode = ""
                email = ""
            } catch {
                errorMessage = "That code couldn't be verified. Send a new one and try again."
            }
            isLoading = false
        }
    }

    private func cancelOtp() {
        otpCode = ""
        errorMessage = nil
        authService.cancelOtpFlow()
    }

    private func resendOtp() {
        otpCode = ""
        errorMessage = nil
        sendOtp()
    }
}
