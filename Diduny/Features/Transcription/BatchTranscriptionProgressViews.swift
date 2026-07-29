import SwiftUI
import UniformTypeIdentifiers

struct BatchTranscriptionRow: View {
    let item: BatchTranscriptionItem
    let service: FileTranscriptionBatchService
    let onRetry: (UUID) -> Void
    @State private var isShowingTranscript = false
    @State private var isShowingCaptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: mediaIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.status.displayName)
                            .foregroundStyle(statusColor)
                        if let duration = item.durationSeconds {
                            metadataSeparator
                            Text(BatchTimeFormatter.string(from: duration))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if item.startedAt != nil {
                            metadataSeparator
                            ElapsedTimeText(item: item)
                        }
                        if let fraction = item.progressFraction, item.status != .completed {
                            metadataSeparator
                            Text(BatchProgressFormatter.percent(fraction))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if let downloaded = item.downloadedBytes {
                            metadataSeparator
                            Text(ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 11))
                    if let error = item.errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 10)
                rowActions
            }

            rowProgress
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(duplicateRowBackground)
        .contentShape(Rectangle())
        .sheet(isPresented: $isShowingTranscript) {
            if let text = item.transcriptionText {
                BatchTranscriptView(fileName: item.sourceURL.lastPathComponent, text: text)
            }
        }
        .sheet(isPresented: $isShowingCaptions) {
            if let artifact = item.sourceCaptionArtifacts.first {
                BatchTranscriptView(
                    title: artifact.provenance.displayName,
                    fileName: item.displayName,
                    text: artifact.text
                )
            }
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        switch item.status {
        case .failed, .cancelled, .partialResult:
            Button("Retry") {
                onRetry(item.id)
            }
            .controlSize(.small)
        case .completed, .duplicate:
            if let text = item.transcriptionText, !text.isEmpty {
                CopyTranscriptButton(text: text, controlSize: .small)

                Button("Transcript") {
                    isShowingTranscript = true
                }
                .controlSize(.small)
            }
            if let recordingID = item.recordingID {
                Button("Recordings") {
                    MainWindowController.shared.showRecording(id: recordingID)
                }
                .controlSize(.small)
            }
        case .authorizationPaused:
            Button("Retry Authorization") {
                service.retryAuthorization()
            }
            .controlSize(.small)
        case .queued, .checkingLink, .checkingDuplicate, .retrievingCaptions,
             .downloading, .preparing, .uploading, .processing, .finalizing:
            if service.isActive(item.id) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Processing \(item.sourceURL.lastPathComponent)")
            }
        }

        if let artifact = item.sourceCaptionArtifacts.first {
            CopyTranscriptButton(
                text: artifact.text,
                label: "Copy Captions",
                controlSize: .small
            )
            Button("Captions") {
                isShowingCaptions = true
            }
            .controlSize(.small)
        }
    }

    private var metadataSeparator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var rowProgress: some View {
        if service.isActive(item.id),
           !item.status.isTerminal,
           let progressFraction = item.progressFraction
        {
            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
    }

    private var mediaIcon: String {
        if item.remoteSource != nil { return "play.rectangle" }
        let type = try? item.sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        return type?.conforms(to: .video) == true ? "film" : "waveform"
    }

    private var iconColor: Color {
        item.status.terminalColor ?? Color("BrandAccentDeep")
    }

    private var statusColor: Color {
        item.status.terminalColor ?? .secondary
    }

    private var duplicateRowBackground: Color {
        item.status == .duplicate ? Color.blue.opacity(0.08) : .clear
    }
}

private struct ElapsedTimeText: View {
    let item: BatchTranscriptionItem
    var prefix = ""

    var body: some View {
        if item.finishedAt != nil {
            Text(formattedElapsed(at: Date()))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(formattedElapsed(at: context.date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedElapsed(at date: Date) -> String {
        let elapsed = item.elapsedTime(at: date) ?? 0
        return prefix + BatchTimeFormatter.string(from: elapsed)
    }
}

private enum BatchTimeFormatter {
    static func string(from duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

enum BatchProgressFormatter {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

private extension BatchTranscriptionItem.Status {
    var terminalColor: Color? {
        switch self {
        case .completed: .green
        case .partialResult: .orange
        case .duplicate: .blue
        case .authorizationPaused: .orange
        case .failed: .red
        case .cancelled: .secondary
        default: nil
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
        case .duplicate: "Duplicate · Transcript reused"
        case .authorizationPaused: "Authorization paused"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

private struct BatchTranscriptView: View {
    @Environment(\.dismiss) private var dismiss

    var title = "Transcript"
    let fileName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.bold())
                    Text(fileName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CopyTranscriptButton(text: text)
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 520)
    }
}

private struct CopyTranscriptButton: View {
    let text: String
    var label = "Copy"
    var controlSize: ControlSize = .regular

    @State private var copiedAt: Date?

    var body: some View {
        Button {
            copyTranscript()
        } label: {
            Label(
                copiedAt == nil ? label : "Copied",
                systemImage: copiedAt == nil ? "doc.on.doc" : "checkmark"
            )
        }
        .controlSize(controlSize)
        .help(copiedAt == nil ? "Copy transcript" : "Transcript copied")
        .accessibilityLabel(copiedAt == nil ? "Copy transcript" : "Transcript copied")
    }

    private func copyTranscript() {
        ClipboardService.shared.copy(text: text, behavior: .raw)

        let timestamp = Date()
        copiedAt = timestamp
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard copiedAt == timestamp else { return }
            copiedAt = nil
        }
    }
}

private extension TranscriptArtifact.Provenance {
    var displayName: String {
        switch self {
        case .youtubeAuthored: "YouTube captions · Authored"
        case .youtubeAutomatic: "YouTube captions · Automatic"
        }
    }
}
