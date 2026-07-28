import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RecordingDetailView: View {
    let recording: Recording
    let parentBatchName: String?
    let onBack: (() -> Void)?
    let onClose: () -> Void

    @State private var playbackService = AudioPlaybackService.shared
    @State private var queueService = RecordingQueueService.shared
    @State private var modelManager = WhisperModelManager.shared
    @State private var selectedWhisperModel: String = SettingsStorage.shared.selectedWhisperModel
    @State private var storage = RecordingsLibraryStorage.shared
    @State private var showRetranscriptionConfirmation = false
    @State private var requestedRetranscriptionProvider: TranscriptionProvider = .cloud
    @State private var requestedWhisperModel: String?
    @State private var title: String
    @State private var description: String
    @State private var showDeleteConfirmation = false

    init(
        recording: Recording,
        parentBatchName: String? = nil,
        onBack: (() -> Void)? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.recording = recording
        self.parentBatchName = parentBatchName
        self.onBack = onBack
        self.onClose = onClose
        _title = State(initialValue: recording.title ?? recording.displayTitle)
        _description = State(initialValue: recording.description ?? recording.remoteSource?.description ?? "")
    }

    private var currentRecording: Recording {
        storage.recordings.first(where: { $0.id == recording.id }) ?? recording
    }

    private var downloadedWhisperModels: [WhisperModelManager.WhisperModel] {
        WhisperModelManager.availableModels.filter { modelManager.isModelDownloaded($0) }
    }

    private var favoriteLanguages: [SupportedLanguage] {
        let codes = SettingsStorage.shared.favoriteLanguages
        return codes.compactMap { SupportedLanguage.language(for: $0) }
    }

    private var otherLanguages: [SupportedLanguage] {
        let favCodes = Set(SettingsStorage.shared.favoriteLanguages)
        return SupportedLanguage.allLanguages.filter { !favCodes.contains($0.code) }
    }

    private var translationPair: TranslationLanguagePair {
        SettingsStorage.shared.resolveTranslationLanguagePair()
    }

    private var queueStatusText: String? {
        guard queueService.currentRecordingId == currentRecording.id,
              let status = queueService.currentJobStatus
        else { return nil }

        switch status {
        case .queued:
            return "Queued..."
        case .uploading:
            return "Uploading..."
        case .processing:
            return "Transcribing..."
        case .finalizing:
            return "Finalizing..."
        case .completed, .error:
            return nil
        }
    }

    private var supportsSpeakerLabels: Bool {
        currentRecording.type.isMeetingLike
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
                .padding(12)

            Divider()

            detailsSection
                .padding(12)

            Divider()

            // Playback
            playbackSection
                .padding(12)

            Divider()

            // Transcription text
            transcriptionSection

            Divider()

            // Actions
            actionsSection
                .padding(12)
        }
        .onExitCommand {
            onClose()
        }
        .alert("Transcribe Again?", isPresented: $showRetranscriptionConfirmation) {
            Button("Transcribe Again") {
                enqueueRequestedRetranscription()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This adds a new transcript version. Earlier transcripts, source captions, and YouTube identity stay available."
            )
        }
        .alert("Delete Recording and Files?", isPresented: $showDeleteConfirmation) {
            Button("Delete Recording", role: .destructive) {
                if playbackService.playingRecordingId == currentRecording.id {
                    playbackService.stop()
                }
                storage.deleteRecording(currentRecording)
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the recording, stored media, transcript history, translations, and every batch reference.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button(action: onBack) {
                    Label("Back to \(parentBatchName ?? "Batch")", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Back to \(parentBatchName ?? "Batch")")
            }

            Image(systemName: currentRecording.libraryIconName)
                .font(.title2)
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(currentRecording.displayTitle)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let sourceDevice = currentRecording.sourceDevice {
                    Text(deviceSummary(sourceDevice))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Esc")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Color(.quaternaryLabelColor).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )

                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.small)
                .accessibilityIdentifier("Close recording detail")
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DETAILS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Recording title", text: $title)
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(2 ... 4)
            if let remoteSource = currentRecording.remoteSource {
                HStack(spacing: 6) {
                    Link(destination: remoteSource.canonicalURL) {
                        Label("Open YouTube Source", systemImage: "link")
                    }
                    .lineLimit(1)
                    if let channel = remoteSource.channelName {
                        Text("· \(channel)").foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.caption)
            }
            HStack {
                Spacer()
                Button("Save Details") {
                    storage.updateDetails(
                        id: currentRecording.id,
                        title: title,
                        description: description
                    )
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        AudioPlaybackControlView(
            recordingId: currentRecording.id,
            fileURL: storage.audioFileURL(for: currentRecording),
            durationHint: currentRecording.durationSeconds
        )
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("TRANSCRIPT HISTORY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if currentRecording.status == .processing {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(queueStatusText ?? "Processing...").foregroundStyle(.secondary)
                    }
                } else if currentRecording.status == .failed {
                    Label(
                        currentRecording.errorMessage ?? "Transcription failed",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }

                let versions = currentRecording.resolvedTranscriptHistory.sorted {
                    $0.createdAt > $1.createdAt
                }
                if versions.isEmpty {
                    Text("No transcription yet")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(versions) { version in
                        transcriptCard(version)
                    }
                }

                if let artifacts = currentRecording.sourceCaptionArtifacts,
                   !artifacts.isEmpty
                {
                    Divider()
                    ForEach(Array(artifacts.enumerated()), id: \.offset) { _, artifact in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(
                                    artifact.provenance == .youtubeAuthored
                                        ? "YouTube Captions · Authored"
                                        : "YouTube Captions · Automatic",
                                    systemImage: "captions.bubble"
                                )
                                .font(.headline)
                                Spacer()
                                Button("Export…") {
                                    exportCaption(artifact)
                                }
                                .controlSize(.small)
                                Button("Copy Captions") {
                                    ClipboardService.shared.copy(
                                        text: artifact.text,
                                        behavior: .raw
                                    )
                                }
                                .controlSize(.small)
                            }
                            Text(artifact.text)
                                .textSelection(.enabled)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(
                            Color(.textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
    }

    private func transcriptCard(_ version: TranscriptVersion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcriptVersionTitle(version)).font(.headline)
                    Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    ClipboardService.shared.copy(text: version.text, behavior: .raw)
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }
            Text(transcriptVersionText(version))
                .textSelection(.enabled)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func transcriptVersionTitle(_ version: TranscriptVersion) -> String {
        switch version.kind {
        case .cloud:
            return "Cloud Transcript"
        case .local:
            return version.modelIdentifier.map { "Local Transcript · \($0)" } ?? "Local Transcript"
        case .translation:
            if let source = version.sourceLanguageCode, let target = version.targetLanguageCode {
                return "Translation · \(source.uppercased()) → \(target.uppercased())"
            }
            return "Translation"
        }
    }

    private func transcriptVersionText(_ version: TranscriptVersion) -> String {
        guard let segments = version.segments, !segments.isEmpty else { return version.text }
        return segments.map { "[\($0.timestampLabel)] \($0.text)" }.joined(separator: "\n\n")
    }

    // MARK: - Actions

    private func exportCaption(_ artifact: TranscriptArtifact) {
        let panel = NSSavePanel()
        panel.title = "Export Source Captions"
        panel.nameFieldStringValue = "YouTube Captions - \(artifact.languageCode).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? artifact.text.write(to: url, atomically: true, encoding: .utf8)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cloud section
            cloudActionsSection

            Divider()

            // Local (Whisper) section
            localActionsSection

            Divider()

            Button("Delete Recording", role: .destructive) {
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Cloud Actions

    private var cloudActionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Cloud", systemImage: "cloud.fill")
                .font(.caption)
                .foregroundColor(Color("BrandAccentDeep"))

            VStack(alignment: .leading, spacing: 6) {
                Button(
                    currentRecording.resolvedTranscriptHistory.isEmpty
                        ? "Transcribe in Cloud"
                        : "Transcribe Again in Cloud…"
                ) {
                    requestRetranscription(provider: .cloud)
                }
                .disabled(currentRecording.status == .processing)

                if supportsSpeakerLabels {
                    Button("Transcribe with Speakers") {
                        queueService.enqueue(
                            [currentRecording.id],
                            action: .transcribeDiarize,
                            providerOverride: .cloud
                        )
                    }
                    .disabled(currentRecording.status == .processing)
                }

                Menu {
                    ForEach(favoriteLanguages) { lang in
                        Button(lang.name) { translate(to: lang.code) }
                    }
                    if !favoriteLanguages.isEmpty && !otherLanguages.isEmpty { Divider() }
                    ForEach(otherLanguages) { lang in
                        Button(lang.name) { translate(to: lang.code) }
                    }
                } label: {
                    HStack {
                        Text(
                            "Translate: \(translationPair.languageA.uppercased()) → \(currentRecording.translationTargetLanguageCode?.uppercased() ?? "Choose Language")"
                        )
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .disabled(currentRecording.status == .processing)

                Text(
                    "Translation direction: \(translationPair.languageA.uppercased()) → \(currentRecording.translationTargetLanguageCode?.uppercased() ?? "choose a language")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Local Actions

    private var localActionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local (Whisper.cpp)", systemImage: "desktopcomputer")
                .font(.caption)
                .foregroundColor(.green)

            if !downloadedWhisperModels.isEmpty {
                HStack(spacing: 8) {
                    Picker("Model:", selection: $selectedWhisperModel) {
                        ForEach(downloadedWhisperModels) { model in
                            Text(model.displayName).tag(model.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)

                    Button(currentRecording.remoteSource == nil ? "Transcribe Locally" : "Transcribe Again Locally…") {
                        let modelName = selectedWhisperModel.isEmpty ? downloadedWhisperModels.first?
                            .name : selectedWhisperModel
                        requestRetranscription(provider: .local, whisperModel: modelName)
                    }
                    .disabled(currentRecording.status == .processing)
                }

                Text("Use this when you want offline processing with the selected Whisper model.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Only Whisper-compatible local models are supported right now. Download one in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Helpers

    private func translate(to languageCode: String) {
        queueService.enqueue(
            [currentRecording.id],
            action: .translate,
            providerOverride: .cloud,
            targetLanguage: languageCode
        )
    }

    private func requestRetranscription(
        provider: TranscriptionProvider,
        whisperModel: String? = nil
    ) {
        requestedRetranscriptionProvider = provider
        requestedWhisperModel = whisperModel
        if currentRecording.remoteSource != nil,
           !(currentRecording.transcriptionText?.isEmpty ?? true)
        {
            showRetranscriptionConfirmation = true
        } else {
            enqueueRequestedRetranscription()
        }
    }

    private func enqueueRequestedRetranscription() {
        queueService.enqueue(
            [currentRecording.id],
            action: .transcribe,
            providerOverride: requestedRetranscriptionProvider,
            whisperModelOverride: requestedWhisperModel
        )
        requestedWhisperModel = nil
    }

    private var iconColor: Color {
        currentRecording.libraryBrandColor
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: currentRecording.createdAt)
    }

    private var formattedDuration: String {
        let minutes = Int(currentRecording.durationSeconds) / 60
        let seconds = Int(currentRecording.durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: currentRecording.fileSizeBytes, countStyle: .file)
    }

    private func deviceSummary(_ sourceDevice: RecordingDeviceInfo) -> String {
        let sampleRate = sourceDevice.sampleRate >= 1000
            ? String(format: "%.1f kHz", sourceDevice.sampleRate / 1000)
            : String(format: "%.0f Hz", sourceDevice.sampleRate)
        return "\(sourceDevice.name) · \(sourceDevice.transportType) · \(sourceDevice.channelCount) ch · \(sampleRate)"
    }
}
