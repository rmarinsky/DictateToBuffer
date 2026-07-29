import SwiftUI

private enum BatchSourceEditor {
    case youtube
    case recordings
}

struct TranscriptionBatchInspectorView: View {
    let batch: TranscriptionBatch
    let onOpenRecording: (UUID) -> Void
    let onClose: () -> Void
    private let chromeProfiles: [ChromeProfile]
    private let showsYouTubeAuthorizationControls: Bool

    @State private var batches = TranscriptionBatchStorage.shared
    @State private var recordings = RecordingsLibraryStorage.shared
    @State private var batchService = FileTranscriptionBatchService.shared
    @State private var name: String
    @State private var description: String
    @State private var showDeleteConfirmation = false
    @State private var saveErrorMessage: String?
    @State private var sourceEditor: BatchSourceEditor?
    @State private var youtubeURLText = ""
    @State private var selectedRecordingIDs = Set<UUID>()
    @State private var selectedChromeProfileID: String
    @State private var rightsAcknowledged: Bool
    @FocusState private var isYouTubeURLInputFocused: Bool

    init(
        batch: TranscriptionBatch,
        onOpenRecording: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.batch = batch
        self.onOpenRecording = onOpenRecording
        self.onClose = onClose
        let profiles = ChromeProfileStore.discover()
        let settings = SettingsStorage.shared
        let storedProfileID = settings.selectedChromeProfileID
        self.chromeProfiles = profiles
        self.showsYouTubeAuthorizationControls = !settings.remoteMediaRightsAcknowledged
            || !profiles.contains(where: { $0.id == storedProfileID })
        _name = State(initialValue: batch.name)
        _description = State(initialValue: batch.description)
        _selectedChromeProfileID = State(
            initialValue: profiles.contains(where: { $0.id == storedProfileID })
                ? storedProfileID ?? ""
                : profiles.first?.id ?? ""
        )
        _rightsAcknowledged = State(initialValue: settings.remoteMediaRightsAcknowledged)
    }

    private var currentBatch: TranscriptionBatch {
        batches.batches.first(where: { $0.id == batch.id }) ?? batch
    }

    private var members: [Recording] {
        let byID = Dictionary(uniqueKeysWithValues: recordings.recordings.map { ($0.id, $0) })
        return currentBatch.recordingIDs.compactMap { byID[$0] }
    }

    private var unattachedWorkItems: [BatchTranscriptionItem] {
        (currentBatch.workItems ?? []).filter { $0.recordingID == nil }
    }

    private var youtubeURLValidation: YouTubeRemoteMediaSource.BatchValidation {
        YouTubeRemoteMediaSource.validateBatch(
            youtubeURLText,
            excludingMediaIDs: existingYouTubeMediaIDs
        )
    }

    private var existingYouTubeMediaIDs: Set<String> {
        Set(
            (currentBatch.workItems ?? []).compactMap { $0.remoteSource?.mediaID }
                + members.compactMap { recording in
                    guard recording.remoteSource?.provider == YouTubeRemoteMediaSource.provider else {
                        return nil
                    }
                    return recording.remoteSource?.mediaID
                }
        )
    }

    private var canAuthorizeYouTube: Bool {
        rightsAcknowledged
            && chromeProfiles.contains(where: { $0.id == selectedChromeProfileID })
    }

    private var availableRecordings: [Recording] {
        let attachedIDs = Set(currentBatch.recordingIDs)
        return recordings.recordings.filter { !attachedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch").font(.caption).foregroundStyle(.secondary)
                    Text(currentBatch.name).font(.headline).lineLimit(1)
                }
                Spacer()
                Button("Close", action: onClose)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DETAILS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextField("Batch title", text: $name)
                        TextField("Description", text: $description, axis: .vertical)
                            .lineLimit(2 ... 5)
                        HStack {
                            Text(
                                "\(currentBatch.status(in: recordings.recordings).rawValue) · \(members.count) recordings · \(currentBatch.createdAt.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Spacer()
                            Button("Save Details") {
                                do {
                                    try batches.update(
                                        batchID: currentBatch.id,
                                        name: name,
                                        description: description
                                    )
                                } catch {
                                    saveErrorMessage = error.localizedDescription
                                }
                            }
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("ATTACHED RECORDINGS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !currentBatch.retryableWorkItems.isEmpty {
                                Button("Retry Failed (\(currentBatch.retryableWorkItems.count))") {
                                    batchService.resume(batch: currentBatch)
                                }
                                .controlSize(.small)
                                .disabled(!batchService.canResume(batch: currentBatch))
                            }
                            Button {
                                ClipboardService.shared.copy(
                                    text: currentBatch.markdown(recordings: recordings.recordings),
                                    behavior: .raw
                                )
                            } label: {
                                Label("Copy All", systemImage: "doc.on.doc")
                            }
                            .controlSize(.small)
                            .help("Copy All Transcriptions")
                            Menu {
                                Button("Choose Files…", systemImage: "doc.badge.plus") {
                                    addFiles()
                                }
                                Button("Paste YouTube URLs…", systemImage: "link") {
                                    sourceEditor = .youtube
                                    selectedRecordingIDs.removeAll()
                                    isYouTubeURLInputFocused = true
                                }
                                Button("Add from Recordings…", systemImage: "waveform") {
                                    sourceEditor = .recordings
                                    selectedRecordingIDs.removeAll()
                                }
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .disabled(batchService.isProcessing)
                        }

                        sourceEditorContent

                        if members.isEmpty {
                            Text(unattachedWorkItems.isEmpty ? "No attached recordings" : "No completed recordings yet")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(members) { recording in
                                HStack(spacing: 10) {
                                    Image(systemName: recording.libraryIconName)
                                        .foregroundStyle(recording.libraryBrandColor)
                                        .frame(width: 24)
                                    Button {
                                        onOpenRecording(recording.id)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recording.displayTitle).lineLimit(1)
                                            Text("\(recording.libraryDisplayName) · \(recording.status.displayName)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    if let latest = recording.resolvedTranscriptHistory.last {
                                        Button("Copy") {
                                            ClipboardService.shared.copy(text: latest.text, behavior: .raw)
                                        }
                                        .controlSize(.small)
                                    }
                                    Button {
                                        onOpenRecording(recording.id)
                                    } label: {
                                        Image(systemName: "chevron.right")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open \(recording.displayTitle)")
                                }
                                .padding(10)
                                .background(
                                    Color(.quaternaryLabelColor).opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }

                        ForEach(unattachedWorkItems) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.red)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayName).lineLimit(1)
                                    Text(item.errorMessage ?? "Ready to retry")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(10)
                            .background(
                                Color(.quaternaryLabelColor).opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }

                    Divider()

                    Button("Delete Batch and \(currentBatch.recordingIDs.count) Recordings", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(!currentBatch.isProcessingClosed)
                }
                .padding(16)
            }
        }
        .alert("Delete Batch and Recordings?", isPresented: $showDeleteConfirmation) {
            Button("Delete Batch and \(currentBatch.recordingIDs.count) Recordings", role: .destructive) {
                if recordings.deleteBatch(currentBatch) {
                    onClose()
                } else {
                    saveErrorMessage = "The batch and its recordings were left unchanged."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes all \(currentBatch.recordingIDs.count) linked recordings and removes shared references from every other batch."
            )
        }
        .alert(
            "Batch Change Failed",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var sourceEditorContent: some View {
        if sourceEditor == .youtube {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Add YouTube URLs").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        sourceEditor = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close YouTube URL editor")
                }
                Text("Paste one video URL per line. Duplicates are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $youtubeURLText)
                    .font(.body.monospaced())
                    .focused($isYouTubeURLInputFocused)
                    .accessibilityLabel("YouTube URLs to add")
                    .frame(height: 112)
                    .padding(6)
                    .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                    }
                if showsYouTubeAuthorizationControls {
                    if chromeProfiles.isEmpty {
                        Text("No Google Chrome profiles were found. Open Chrome once, then try again.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Picker("Chrome profile", selection: $selectedChromeProfileID) {
                            ForEach(chromeProfiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .controlSize(.small)
                    }
                    if !SettingsStorage.shared.remoteMediaRightsAcknowledged {
                        Toggle(
                            "I own this content or have permission to transcribe it.",
                            isOn: $rightsAcknowledged
                        )
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
                HStack(spacing: 10) {
                    Text("\(youtubeURLValidation.sources.count) valid")
                        .foregroundStyle(.green)
                    if youtubeURLValidation.duplicateCount > 0 {
                        Text("\(youtubeURLValidation.duplicateCount) duplicate\(youtubeURLValidation.duplicateCount == 1 ? "" : "s")")
                    }
                    if !youtubeURLValidation.invalidValues.isEmpty {
                        Text("\(youtubeURLValidation.invalidValues.count) invalid")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Paste") {
                        youtubeURLText = NSPasteboard.general.string(forType: .string) ?? youtubeURLText
                    }
                    Button("Add \(youtubeURLValidation.sources.count) URL\(youtubeURLValidation.sources.count == 1 ? "" : "s")") {
                        addYouTubeURLs()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(youtubeURLValidation.sources.isEmpty || !canAuthorizeYouTube)
                }
            }
            .padding(10)
            .background(
                Color(.quaternaryLabelColor).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
        } else if sourceEditor == .recordings {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Add from Recordings").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        sourceEditor = nil
                        selectedRecordingIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close recording picker")
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(availableRecordings) { recording in
                            Toggle(isOn: Binding(
                                get: { selectedRecordingIDs.contains(recording.id) },
                                set: { selected in
                                    if selected { selectedRecordingIDs.insert(recording.id) }
                                    else { selectedRecordingIDs.remove(recording.id) }
                                }
                            )) {
                                Text(recording.displayTitle).lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 180)
                HStack {
                    Spacer()
                    Button("Add \(selectedRecordingIDs.count) Recording\(selectedRecordingIDs.count == 1 ? "" : "s")") {
                        addExistingRecordings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRecordingIDs.isEmpty)
                }
            }
            .padding(10)
            .background(
                Color(.quaternaryLabelColor).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
    }

    private func addFiles() {
        guard let files = ImportedMediaPicker.selectFiles(), !files.isEmpty else { return }
        append(urls: files, remoteSources: [], existingRecordingIDs: [])
    }

    private func addYouTubeURLs() {
        let validation = youtubeURLValidation
        guard !validation.sources.isEmpty, canAuthorizeYouTube else { return }
        SettingsStorage.shared.selectedChromeProfileID = selectedChromeProfileID
        SettingsStorage.shared.remoteMediaRightsAcknowledged = true
        guard append(urls: [], remoteSources: validation.sources, existingRecordingIDs: []) else {
            return
        }
        youtubeURLText = validation.invalidValues.joined(separator: "\n")
        if validation.invalidValues.isEmpty {
            sourceEditor = nil
        }
    }

    private func addExistingRecordings() {
        guard append(
            urls: [],
            remoteSources: [],
            existingRecordingIDs: availableRecordings
                .filter { selectedRecordingIDs.contains($0.id) }
                .map(\.id)
        ) else { return }
        selectedRecordingIDs.removeAll()
        sourceEditor = nil
    }

    @discardableResult
    private func append(
        urls: [URL],
        remoteSources: [YouTubeRemoteMediaSource],
        existingRecordingIDs: [UUID]
    ) -> Bool {
        let accepted = batchService.append(
            to: currentBatch,
            urls: urls,
            remoteSources: remoteSources,
            existingRecordingIDs: existingRecordingIDs
        )
        guard accepted else {
            saveErrorMessage = batchService.batchError
                ?? "Another transcription batch is active. Finish it before updating this batch."
            return false
        }
        if !urls.isEmpty || !remoteSources.isEmpty {
            BatchTranscriptionWindowController.shared.showWindow()
        }
        return true
    }
}

struct NewTranscriptionBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recordings: [Recording]
    @State private var name = ""
    @State private var description = ""
    @State private var files: [URL] = []
    @State private var urlText = ""
    @State private var selectedRecordingIDs = Set<UUID>()
    @State private var validationError: String?
    @State private var showRecordingPicker = false
    @FocusState private var isYouTubeURLInputFocused: Bool

    private var canCreate: Bool {
        !files.isEmpty || !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedRecordingIDs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Transcription Batch").font(.title2.bold())
            TextField("Batch name (optional)", text: $name)
            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(2 ... 4)

            HStack {
                Button("Add Files…", systemImage: "plus") {
                    files.append(contentsOf: ImportedMediaPicker.selectFiles() ?? [])
                }
                Button("Add YouTube URLs", systemImage: "link") {
                    isYouTubeURLInputFocused = true
                }
                Button("Add from Recordings", systemImage: "waveform") {
                    showRecordingPicker.toggle()
                }
            }
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 6) {
                Text("YOUTUBE URLS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $urlText)
                    .font(.body.monospaced())
                    .focused($isYouTubeURLInputFocused)
                    .accessibilityLabel("YouTube URLs")
                    .frame(height: 64)
                    .padding(6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.separatorColor))
                    }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("SELECTED SOURCES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if files.isEmpty, urlLines.isEmpty, selectedRecordingIDs.isEmpty, !showRecordingPicker {
                            Text("Add files, YouTube URLs, or existing recordings.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 36)
                        }

                        ForEach(files, id: \.self) { file in
                            sourceRow(file.lastPathComponent, icon: "doc") {
                                files.removeAll { $0 == file }
                            }
                        }
                        ForEach(urlLines, id: \.self) { url in
                            sourceRow(url, icon: "play.rectangle") {
                                removeURL(url)
                            }
                        }
                        ForEach(recordings.filter { selectedRecordingIDs.contains($0.id) }) { recording in
                            sourceRow(recording.displayTitle, icon: recording.libraryIconName) {
                                selectedRecordingIDs.remove(recording.id)
                            }
                        }

                        if showRecordingPicker {
                            Divider().padding(.vertical, 6)
                            Text("RECORDINGS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 6)
                            ForEach(recordings.filter { !selectedRecordingIDs.contains($0.id) }) { recording in
                                Toggle(isOn: Binding(
                                    get: { selectedRecordingIDs.contains(recording.id) },
                                    set: { selected in
                                        if selected { selectedRecordingIDs.insert(recording.id) }
                                        else { selectedRecordingIDs.remove(recording.id) }
                                    }
                                )) {
                                    Text(recording.displayTitle).lineLimit(1)
                                }
                                .toggleStyle(.checkbox)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 260)
            }
            .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separatorColor)) }

            if let validationError {
                Text(validationError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create and Transcribe") { createBatch() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 460)
    }

    private var urlLines: [String] {
        urlText.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func sourceRow(_ title: String, icon: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(title).lineLimit(1)
            Spacer()
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func removeURL(_ url: String) {
        urlText = urlLines.filter { $0 != url }.joined(separator: "\n")
    }

    private func createBatch() {
        do {
            let remoteSources = try YouTubeRemoteMediaSource.normalizeBatch(urlText)
            let batchService = FileTranscriptionBatchService.shared
            let accepted = batchService.beginBatch(
                urls: files,
                remoteSources: remoteSources,
                name: name,
                description: description,
                existingRecordingIDs: recordings
                    .filter { selectedRecordingIDs.contains($0.id) }
                    .map(\.id)
            )
            guard accepted else {
                validationError = batchService.batchError
                    ?? "Another transcription batch is active. Finish or retry it before creating a new batch."
                return
            }
            if !files.isEmpty || !remoteSources.isEmpty {
                BatchTranscriptionWindowController.shared.showWindow()
            }
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }
}
