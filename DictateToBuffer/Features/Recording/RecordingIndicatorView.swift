import SwiftUI

struct RecordingIndicatorView: View {
    @EnvironmentObject var appState: AppState
    @State private var isPulsing = false
    @State private var timerTick = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            statusIcon
                .font(.system(size: 12))

            // Status text
            statusText
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundView)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            // Start timer if already recording when view appears
            if appState.recordingState == .recording {
                startTimer()
            }
        }
        .onChange(of: appState.recordingState) { _, newState in
            if newState == .recording {
                startTimer()
            } else {
                stopTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            timerTick += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerTick = 0
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.recordingState {
        case .recording:
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.2 : 1.0)

        case .processing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 10, height: 10)

        case .success:
            Image(systemName: "checkmark")
                .foregroundColor(.green)

        case .error:
            Image(systemName: "xmark")
                .foregroundColor(.red)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        // Reference timerTick to trigger re-render every second during recording
        let _ = timerTick
        switch appState.recordingState {
        case .recording:
            Text(formattedDuration)

        case .processing:
            Text("...")

        case .success:
            Text("Copied")

        case .error:
            Text("Error")

        case .idle:
            EmptyView()
        }
    }

    private var backgroundView: some View {
        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
    }

    private var formattedDuration: String {
        let duration = Int(appState.recordingDuration)
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Visual Effect Blur for macOS

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    RecordingIndicatorView()
        .environmentObject(AppState())
        .frame(width: 150, height: 40)
}
