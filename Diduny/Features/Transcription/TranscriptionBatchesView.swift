import SwiftUI

struct TranscriptionBatchesView: View {
    @State private var batches = TranscriptionBatchStorage.shared
    @State private var recordings = RecordingsLibraryStorage.shared
    @State private var selectedBatchID: UUID?
    @State private var query = ""
    @State private var memberQuery = ""
    @State private var showComposer = false
    @State private var editingBatch: TranscriptionBatch?
    @State private var deletingBatch: TranscriptionBatch?

    private var selectedBatch: TranscriptionBatch? {
        batches.batches.first(where: { $0.id == selectedBatchID })
    }

    private var filteredBatches: [TranscriptionBatch] {
        batches.batches.filter { $0.matches(query, recordings: recordings.recordings) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedBatch {
                detail(selectedBatch)
            } else {
                batchList
            }
        }
        .sheet(isPresented: $showComposer) {
            NewTranscriptionBatchSheet(recordings: recordings.recordings)
        }
        .sheet(item: $editingBatch) { batch in
            TranscriptionBatchEditor(batch: batch) { name, description in
                try? batches.update(batchID: batch.id, name: name, description: description)
            }
        }
        .alert(
            "Delete Batch and Recordings?",
            isPresented: Binding(
                get: { deletingBatch != nil },
                set: { if !$0 { deletingBatch = nil } }
            ),
            presenting: deletingBatch
        ) { batch in
            Button("Delete Batch and \(batch.recordingIDs.count) Recordings", role: .destructive) {
                recordings.deleteBatch(batch)
                selectedBatchID = nil
                deletingBatch = nil
            }
            Button("Cancel", role: .cancel) { deletingBatch = nil }
        } message: { batch in
            Text(
                "This permanently deletes all \(batch.recordingIDs.count) linked recordings from Library. Shared recordings will also disappear from every other batch."
            )
        }
    }

    private var batchList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Batches").font(.title2.bold())
                    Text("Durable groups of files, URLs, and Library recordings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                searchField("Search batches", text: $query)
                Button {
                    showComposer = true
                } label: {
                    Label("New Batch", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if batches.batches.isEmpty {
                ContentUnavailableView(
                    "No Batches Yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("Create a batch to keep grouped transcription results.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredBatches.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredBatches.enumerated()), id: \.element.id) { index, batch in
                            Button {
                                selectedBatchID = batch.id
                            } label: {
                                batchRow(batch)
                            }
                            .buttonStyle(.plain)
                            if index < filteredBatches.count - 1 { Divider() }
                        }
                    }
                }
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                }
            }
        }
        .padding(24)
    }

    private func batchRow(_ batch: TranscriptionBatch) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(batch.name).font(.headline)
                if !batch.description.isEmpty {
                    Text(batch.description).lineLimit(1).foregroundStyle(.secondary)
                }
                Text("\(batch.recordingIDs.count) recordings · \(batch.status(in: recordings.recordings).rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(batch.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private func detail(_ batch: TranscriptionBatch) -> some View {
        let memberIDs = Set(batch.recordingIDs)
        let members = recordings.recordings
            .filter { memberIDs.contains($0.id) }
            .sorted {
                (batch.recordingIDs.firstIndex(of: $0.id) ?? .max)
                    < (batch.recordingIDs.firstIndex(of: $1.id) ?? .max)
            }
            .filter { recording in
                memberQuery.isEmpty
                    || [
                        recording.sourceFileName,
                        recording.remoteSource?.title,
                        recording.transcriptionText,
                    ].compactMap { $0 }.contains {
                        $0.localizedCaseInsensitiveContains(memberQuery)
                    }
            }
        let unresolvedItems = (batch.workItems ?? []).filter { item in
            item.recordingID == nil
                && (memberQuery.isEmpty
                    || item.displayName.localizedCaseInsensitiveContains(memberQuery)
                    || (item.errorMessage?.localizedCaseInsensitiveContains(memberQuery) ?? false))
        }
        let canRetry = batch.workItems?.contains {
            $0.status != .completed && $0.status != .duplicate
        } == true

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Button {
                    selectedBatchID = nil
                    memberQuery = ""
                } label: {
                    Label("All Batches", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Delete", role: .destructive) { deletingBatch = batch }
                    .disabled(!batch.isProcessingClosed)
                Button("Edit") { editingBatch = batch }
                if canRetry {
                    Button("Retry Failed") {
                        FileTranscriptionBatchService.shared.resume(batch: batch)
                        BatchTranscriptionWindowController.shared.showWindow()
                    }
                }
                Button {
                    ClipboardService.shared.copy(
                        text: batch.markdown(recordings: recordings.recordings),
                        behavior: .raw
                    )
                } label: {
                    Label("Copy Markdown", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(batch.name).font(.title2.bold())
                if !batch.description.isEmpty { Text(batch.description).foregroundStyle(.secondary) }
                Text(
                    "\(batch.status(in: recordings.recordings).rawValue) · \(batch.recordingIDs.count) recordings · Created \(batch.createdAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            searchField("Search members", text: $memberQuery)

            if members.isEmpty && unresolvedItems.isEmpty {
                ContentUnavailableView(
                    memberQuery.isEmpty ? "No Recordings" : "No Results",
                    systemImage: memberQuery.isEmpty ? "waveform" : "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(unresolvedItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.displayName).font(.headline)
                                    Text(item.errorMessage ?? "Not completed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(16)
                            Divider()
                        }
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, recording in
                            HStack(spacing: 12) {
                                Image(systemName: recording.libraryIconName)
                                    .foregroundStyle(recording.libraryBrandColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recording.remoteSource?.title ?? recording.sourceFileName ?? recording.libraryDisplayName)
                                        .font(.headline)
                                    Text("\(recording.libraryDisplayName) · \(recording.status.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let preview = recording.transcriptionText {
                                        Text(preview).lineLimit(2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(16)
                            if index < members.count - 1 { Divider() }
                        }
                    }
                }
                .background(Color(.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                }
            }
        }
        .padding(24)
    }

    private func searchField(_ prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(Color(.quaternaryLabelColor).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TranscriptionBatchEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    let onSave: (String, String) -> Void

    init(batch: TranscriptionBatch, onSave: @escaping (String, String) -> Void) {
        _name = State(initialValue: batch.name)
        _description = State(initialValue: batch.description)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Batch").font(.title2.bold())
            TextField("Batch name", text: $name)
            TextField("Description", text: $description, axis: .vertical)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(name, description)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct NewTranscriptionBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recordings: [Recording]
    @State private var name = ""
    @State private var description = ""
    @State private var files: [URL] = []
    @State private var urlText = ""
    @State private var selectedRecordingIDs = Set<UUID>()
    @State private var validationError: String?

    private var canCreate: Bool {
        !files.isEmpty || !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedRecordingIDs.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Transcription Batch").font(.title2.bold())
            TextField("Batch name (optional)", text: $name)
            TextField("Description (optional)", text: $description, axis: .vertical)

            GroupBox("Files") {
                HStack {
                    Text(files.isEmpty ? "No files selected" : "\(files.count) files selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose Files…") {
                        files = ImportedMediaPicker.selectFiles() ?? files
                    }
                }
                .padding(6)
            }

            GroupBox("YouTube URLs") {
                TextEditor(text: $urlText)
                    .font(.body.monospaced())
                    .frame(height: 64)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Color(.separatorColor))
                    }
                    .padding(6)
            }

            GroupBox("Library") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(recordings) { recording in
                            Toggle(isOn: Binding(
                                get: { selectedRecordingIDs.contains(recording.id) },
                                set: { selected in
                                    if selected { selectedRecordingIDs.insert(recording.id) }
                                    else { selectedRecordingIDs.remove(recording.id) }
                                }
                            )) {
                                Text(recording.remoteSource?.title ?? recording.sourceFileName ?? recording.libraryDisplayName)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 150)
            }

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
        .frame(width: 620, height: 600)
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
