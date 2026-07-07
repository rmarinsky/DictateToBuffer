import AppKit
import SwiftUI

struct AccountSettingsView: View {
    // Proxy state
    @State private var proxyBaseURL: String = SettingsStorage.shared.proxyBaseURL
    @State private var isTestingProxy = false
    @State private var proxyTestResult: ProxyTestResult?
    @State private var isRefreshingConfig = false
    @State private var billingError: String?
    @State private var isBillingActionLoading = false

    private var authService: AuthService { AuthService.shared }

    enum ProxyTestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section("Account") {
#if DEV_BUILD
                HStack {
                    TextField("Proxy URL", text: $proxyBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: proxyBaseURL) { _, newValue in
                            SettingsStorage.shared.proxyBaseURL = newValue
                        }
                }
#endif

                AccountSignInView()

#if DEV_BUILD
                HStack(spacing: 8) {
                    Button("Test Connection") {
                        testProxyConnection()
                    }
                    .buttonStyle(.bordered)
                    .disabled(proxyBaseURL.isEmpty || isTestingProxy)

                    Button("Refresh Config") {
                        refreshRemoteConfig()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshingConfig)

                    if isTestingProxy || isRefreshingConfig {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()
                }

                if let result = proxyTestResult {
                    testResultView(result)
                }
#endif
            }

            billingSection

            cloudUsageSection

            usageSection
        }
        .formStyle(.grouped)
        .onAppear {
            proxyBaseURL = SettingsStorage.shared.proxyBaseURL
            if authService.isLoggedIn {
                Task { await refreshAccountData() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard authService.isLoggedIn else { return }
            Task { await refreshAccountData(syncBilling: true) }
        }
    }

    // MARK: - Billing Section

    @ViewBuilder
    private var billingSection: some View {
        if authService.isLoggedIn, BillingService.shared.hasVisibleBillingState {
            Section("Diduny Pro") {
                let billing = BillingService.shared

                if let status = billing.cachedStatus {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(billingTitle(status))
                                    .font(.headline)
                                Text(billingSubtitle(status))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(billingBadge(status))
                                .font(.caption.weight(.bold))
                                .foregroundColor(billingBadgeColor(status))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(billingBadgeColor(status).opacity(0.14), in: Capsule())
                        }

                        HStack(spacing: 8) {
                            billingPrimaryAction(status)

                            Button {
                                Task { await refreshAccountData(syncBilling: true) }
                            } label: {
                                Label("Refresh Status", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(billing.isLoading || isBillingActionLoading)

                            if billing.isLoading || isBillingActionLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                } else if billing.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Free")
                            .font(.headline)
                        Text("Cloud dictation includes 5 hours per month.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Upgrade to Diduny Pro") {
                            performBillingAction { try await BillingService.shared.startCheckout() }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                if let billingError {
                    Text(billingError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Cloud Usage Section

    @ViewBuilder
    private var cloudUsageSection: some View {
        if authService.isLoggedIn {
            Section("Cloud Usage") {
                let usageService = UsageService.shared

                if let usage = usageService.cachedUsage {
                    if usage.isUnlimited {
                        HStack {
                            Image(systemName: "infinity")
                                .foregroundColor(.green)
                            Text(unlimitedUsageLabel(usage))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: min(usageService.usagePercent, 1.0))
                                .tint(usageProgressColor(usageService.usagePercent))

                            HStack {
                                Text(String(format: "%.1fh / %.0fh used this month",
                                            usage.usedHours,
                                            usage.limitHours ?? 5))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(usageService.formattedRemaining)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(usageProgressColor(usageService.usagePercent))
                            }
                        }
                    }
                } else if usageService.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Usage data not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button {
                        Task { await UsageService.shared.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(usageService.isLoading)
                }
            }
        }
    }

    @ViewBuilder
    private func billingPrimaryAction(_ status: BillingStatusResponse) -> some View {
        switch status.status {
        case .checkoutPending:
            Button("Refresh Status") {
                Task { await refreshAccountData(syncBilling: true) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .active:
            if status.entitlement == .paid {
                Button("Cancel Renewal") {
                    performBillingAction { try await BillingService.shared.cancelRenewal() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Upgrade to Diduny Pro") {
                    performBillingAction { try await BillingService.shared.startCheckout() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case .cancelled:
            Button("Resume Renewal") {
                performBillingAction { try await BillingService.shared.resumeRenewal() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .expired, .pastDue:
            Button("Upgrade to Diduny Pro") {
                performBillingAction { try await BillingService.shared.startCheckout() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func billingTitle(_ status: BillingStatusResponse) -> String {
        switch (status.entitlement, status.status) {
        case (.grant, _):
            "Unlimited Access"
        case (.legacyUnlimited, _):
            "Unlimited Access"
        case (.paid, .cancelled):
            "Diduny Pro"
        case (.paid, _):
            "Diduny Pro"
        case (_, .checkoutPending):
            "Checkout Pending"
        default:
            "Free"
        }
    }

    private func billingSubtitle(_ status: BillingStatusResponse) -> String {
        switch status.status {
        case .active where status.entitlement == .paid:
            if let renewsAt = formatISODate(status.renewsAt) {
                return "Renews \(renewsAt)"
            }
            return "Unlimited cloud usage"
        case .cancelled:
            if let activeUntil = formatISODate(status.activeUntil) {
                return "Active until \(activeUntil)"
            }
            return "Renewal cancelled"
        case .checkoutPending:
            return "Waiting for WayForPay confirmation"
        case .active where status.entitlement == .grant:
            return "Manual whitelist grant"
        case .active where status.entitlement == .legacyUnlimited:
            return "Legacy unlimited access"
        case .pastDue:
            return "Payment needs attention"
        case .expired:
            return "5 hours of cloud usage per month"
        default:
            return "5 hours of cloud usage per month"
        }
    }

    private func billingBadge(_ status: BillingStatusResponse) -> String {
        switch status.entitlement {
        case .paid:
            status.cancelAtPeriodEnd ? "CANCELLED" : "PRO"
        case .grant:
            "GRANT"
        case .legacyUnlimited:
            "LEGACY"
        case .free:
            status.status == .checkoutPending ? "PENDING" : "FREE"
        }
    }

    private func billingBadgeColor(_ status: BillingStatusResponse) -> Color {
        switch status.entitlement {
        case .paid:
            return status.cancelAtPeriodEnd ? .orange : Color("BrandAccentDeep")
        case .grant, .legacyUnlimited:
            return .green
        case .free:
            return status.status == .checkoutPending ? .orange : .secondary
        }
    }

    private func unlimitedUsageLabel(_ usage: UsageResponse) -> String {
        switch usage.entitlement {
        case "paid":
            "Unlimited cloud usage"
        case "grant":
            "Unlimited (whitelisted)"
        case "legacy_unlimited":
            "Unlimited (legacy)"
        default:
            "Unlimited"
        }
    }

    private func refreshAccountData(syncBilling: Bool = false) async {
        if syncBilling {
            try? await BillingService.shared.sync(
                orderReference: BillingService.shared.cachedStatus?.pendingOrderReference
            )
        } else {
            await BillingService.shared.refresh()
        }
        await UsageService.shared.refresh()
    }

    private func performBillingAction(_ action: @escaping () async throws -> Void) {
        isBillingActionLoading = true
        billingError = nil
        Task {
            do {
                try await action()
                await refreshAccountData()
            } catch {
                billingError = error.localizedDescription
            }
            isBillingActionLoading = false
        }
    }

    private func formatISODate(_ value: String?) -> String? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return nil }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func usageProgressColor(_ percent: Double) -> Color {
        if percent < 0.5 { return .green }
        if percent < 0.8 { return .yellow }
        return .red
    }

    // MARK: - Usage Section

    @ViewBuilder
    private var usageSection: some View {
        Section("Usage") {
            let recordings = RecordingsLibraryStorage.shared.recordings
            let statistics = RecordingStatistics(recordings: recordings)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    Text("Total recording time")
                    Spacer()
                    Text(formatDuration(statistics.totalDurationSeconds))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)

                Divider()

                usageRow(icon: "mic.fill", label: "Voice dictation", duration: statistics.voiceDurationSeconds, color: Color("BrandAccentDeep"))
                usageRow(icon: "globe", label: "Translation", duration: statistics.translationDurationSeconds, color: .green)
                usageRow(icon: "person.3.fill", label: "Meetings", duration: statistics.meetingDurationSeconds, color: .orange)
                usageRow(icon: "doc.fill", label: "Imported files", duration: statistics.importedFileDurationSeconds, color: .brown)
                usageRow(icon: "play.rectangle.fill", label: "YouTube", duration: statistics.youtubeDurationSeconds, color: .red)

                Divider()

                HStack {
                    Image(systemName: "number")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                    Text("Total recordings")
                    Spacer()
                    Text("\(statistics.recordingCount)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }

            Text("Recording time is tracked locally. This data will be used to show how much time Diduny has saved you.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func usageRow(icon: String, label: String, duration: TimeInterval, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(formatDuration(duration))
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func testResultView(_ result: ProxyTestResult) -> some View {
        HStack {
            switch result {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connection successful")
                    .foregroundColor(.green)
            case let .failure(message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.red)
            }
        }
        .font(.caption)
    }

    private func testProxyConnection() {
        isTestingProxy = true
        proxyTestResult = nil

        Task {
            let urlString = proxyBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: "\(urlString)/api/v1/health") else {
                await MainActor.run {
                    proxyTestResult = .failure("Invalid proxy URL")
                    isTestingProxy = false
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10

            await AuthService.shared.authenticatedRequest(&request)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                await MainActor.run {
                    if (200 ... 299).contains(statusCode) {
                        proxyTestResult = .success
                    } else if statusCode == 401 {
                        proxyTestResult = .failure("Unauthorized \u{2014} check proxy token")
                    } else {
                        proxyTestResult = .failure("Status \(statusCode)")
                    }
                    isTestingProxy = false
                }
            } catch {
                await MainActor.run {
                    proxyTestResult = .failure(error.localizedDescription)
                    isTestingProxy = false
                }
            }
        }
    }

    private func refreshRemoteConfig() {
        isRefreshingConfig = true

        Task {
            await RemoteConfigService.shared.forceRefresh()
            await MainActor.run {
                isRefreshingConfig = false
            }
        }
    }
}

#Preview {
    AccountSettingsView()
        .frame(width: 500, height: 600)
}
