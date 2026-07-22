import SwiftUI
import UniformTypeIdentifiers

struct CurrentFileProgressView: View {
    let item: BatchTranscriptionItem
    let position: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Current file", systemImage: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(position) of \(totalCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(item.sourceURL.lastPathComponent)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .help(item.sourceURL.lastPathComponent)

            HStack(spacing: 6) {
                Text(item.status.displayName)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                ElapsedTimeText(item: item, prefix: "Elapsed ")
                Spacer()
                if let fraction = item.progressFraction {
                    Text(BatchProgressFormatter.percent(fraction))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .font(.system(size: 11))

            if let fraction = item.progressFraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 0.5)
        )
    }
}

struct BatchTranscriptionRow: View {
    let item: BatchTranscriptionItem
    let service: FileTranscriptionBatchService
    @State private var isShowingTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: mediaIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 28, height: 28)
                    .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.sourceURL.lastPathComponent)
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
        .contentShape(Rectangle())
        .sheet(isPresented: $isShowingTranscript) {
            if let text = item.transcriptionText {
                BatchTranscriptView(fileName: item.sourceURL.lastPathComponent, text: text)
            }
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        switch item.status {
        case .failed, .cancelled:
            Button("Retry") {
                service.retry(ids: [item.id])
            }
            .controlSize(.small)
        case .completed:
            if let text = item.transcriptionText, !text.isEmpty {
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
        case .queued, .preparing, .uploading, .processing, .finalizing:
            EmptyView()
        }
    }

    private var metadataSeparator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var rowProgress: some View {
        if shouldShowIndeterminateProgress {
            ProgressView()
                .progressViewStyle(.linear)
        } else {
            ProgressView(value: rowProgressFraction)
                .progressViewStyle(.linear)
                .tint(progressColor)
        }
    }

    private var shouldShowIndeterminateProgress: Bool {
        service.currentItemID == item.id
            && !item.status.isTerminal
            && item.progressFraction == nil
    }

    private var rowProgressFraction: Double {
        item.status == .completed ? 1 : (item.progressFraction ?? 0)
    }

    private var progressColor: Color {
        item.status.terminalColor ?? .accentColor
    }

    private var mediaIcon: String {
        let type = try? item.sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        return type?.conforms(to: .video) == true ? "film" : "waveform"
    }

    private var iconColor: Color {
        item.status.terminalColor ?? Color("BrandAccentDeep")
    }

    private var statusColor: Color {
        item.status.terminalColor ?? .secondary
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
        case .failed: .red
        case .cancelled: .secondary
        default: nil
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .preparing: "Preparing audio…"
        case .uploading: "Uploading…"
        case .processing: "Transcribing…"
        case .finalizing: "Finishing…"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

private struct BatchTranscriptView: View {
    @Environment(\.dismiss) private var dismiss

    let fileName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcript")
                        .font(.title2.bold())
                    Text(fileName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
