import SwiftUI

struct TranscriptionBatchInspectorView: View {
    let batch: TranscriptionBatch
    let onOpenRecording: (UUID) -> Void
    let onClose: () -> Void

    @State private var batches = TranscriptionBatchStorage.shared
    @State private var recordings = RecordingsLibraryStorage.shared
    @State private var name: String
    @State private var description: String
    @State private var showDeleteConfirmation = false
    @State private var saveErrorMessage: String?

    init(
        batch: TranscriptionBatch,
        onOpenRecording: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.batch = batch
        self.onOpenRecording = onOpenRecording
        self.onClose = onClose
        _name = State(initialValue: batch.name)
        _description = State(initialValue: batch.description)
    }

    private var currentBatch: TranscriptionBatch {
        batches.batches.first(where: { $0.id == batch.id }) ?? batch
    }

    private var members: [Recording] {
        let byID = Dictionary(uniqueKeysWithValues: recordings.recordings.map { ($0.id, $0) })
        return currentBatch.recordingIDs.compactMap { byID[$0] }
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
                            Button {
                                ClipboardService.shared.copy(
                                    text: currentBatch.markdown(recordings: recordings.recordings),
                                    behavior: .raw
                                )
                            } label: {
                                Label("Copy All Transcriptions", systemImage: "doc.on.doc")
                            }
                            .controlSize(.small)
                        }

                        if members.isEmpty {
                            Text("No attached recordings")
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
                recordings.deleteBatch(currentBatch)
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently deletes all \(currentBatch.recordingIDs.count) linked recordings and removes shared references from every other batch."
            )
        }
        .alert(
            "Couldn't Save Batch",
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
    @State private var showURLField = false
    @State private var showRecordingPicker = false

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
                    showURLField.toggle()
                }
                Button("Add from Recordings", systemImage: "waveform") {
                    showRecordingPicker.toggle()
                }
            }
            .controlSize(.small)

            if showURLField {
                TextEditor(text: $urlText)
                    .font(.body.monospaced())
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
            FileTranscriptionBatchService.shared.beginBatch(
                urls: files,
                remoteSources: remoteSources,
                name: name,
                description: description,
                existingRecordingIDs: recordings
                    .filter { selectedRecordingIDs.contains($0.id) }
                    .map(\.id)
            )
            if !files.isEmpty || !remoteSources.isEmpty {
                BatchTranscriptionWindowController.shared.showWindow()
            }
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }
}
