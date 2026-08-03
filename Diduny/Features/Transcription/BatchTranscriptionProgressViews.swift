import SwiftUI

struct BatchTranscriptionStatusView: View {
    let item: BatchTranscriptionItem
    let service: FileTranscriptionBatchService
    let onRetry: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if service.isActive(item.id), !item.status.isTerminal {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Processing \(item.displayName)")
                }
                Text(item.status.displayName)
                    .foregroundStyle(item.status.statusColor)
                    .lineLimit(1)
                if let progress = item.progressFraction, !item.status.isTerminal {
                    Text("\(Int((progress * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                retryButton
            }
            .font(.caption)

            if service.isActive(item.id),
               !item.status.isTerminal,
               let progress = item.progressFraction
            {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Progress for \(item.displayName)")
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            }

            if let error = visibleErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var visibleErrorMessage: String? {
        item.errorMessage
            ?? (service.items.contains(where: { $0.id == item.id }) ? service.batchError : nil)
    }

    @ViewBuilder
    private var retryButton: some View {
        switch item.status {
        case .failed, .cancelled, .partialResult:
            Button("Retry") { onRetry(item.id) }
                .controlSize(.mini)
        case .authorizationPaused:
            Button("Retry") { service.retryAuthorization() }
                .controlSize(.mini)
        default:
            EmptyView()
        }
    }
}

private extension BatchTranscriptionItem.Status {
    var statusColor: Color {
        switch self {
        case .authorizationPaused, .partialResult: .orange
        case .failed: .red
        default: .secondary
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .checkingLink: "Checking link…"
        case .checkingDuplicate: "Checking duplicate…"
        case .retrievingCaptions: "Retrieving captions…"
        case .downloading: "Downloading audio…"
        case .preparing: "Preparing audio…"
        case .uploading: "Uploading…"
        case .processing: "Transcribing…"
        case .finalizing: "Finishing…"
        case .completed: "Completed"
        case .partialResult: "Partial result"
        case .duplicate: "Transcript reused"
        case .authorizationPaused: "Authorization paused"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}
