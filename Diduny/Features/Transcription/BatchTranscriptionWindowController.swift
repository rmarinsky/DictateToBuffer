import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BatchTranscriptionWindowController {
    static let shared = BatchTranscriptionWindowController()

    private var window: NSWindow?
    private var urlImportWindow: NSWindow?
    private var windowDelegate: BatchTranscriptionWindowDelegate?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    private init() {}

    func selectFilesForNewBatch() {
        guard let urls = ImportedMediaPicker.selectFiles(), !urls.isEmpty else { return }
        FileTranscriptionBatchService.shared.beginBatch(urls: urls)
        showWindow()
    }

    func addFiles() {
        guard let urls = ImportedMediaPicker.selectFiles(), !urls.isEmpty else { return }
        let service = FileTranscriptionBatchService.shared
        service.add(urls: urls)
        service.startIfNeeded()
        showWindow()
    }

    func selectYouTubeURLsForNewBatch() {
        presentYouTubeURLImporter(startsNewBatch: true)
    }

    func addYouTubeURLs() {
        presentYouTubeURLImporter(startsNewBatch: false)
    }

    func openYouTubeInSelectedChrome() {
        guard let profileID = SettingsStorage.shared.selectedChromeProfileID else { return }
        openYouTubeInChrome(profileID: profileID)
    }

    func openYouTubeInChrome(profileID: String) {
        guard let chromeURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.google.Chrome"
        ),
            let youtubeURL = URL(string: "https://www.youtube.com/")
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [
            "--profile-directory=\(profileID)",
            youtubeURL.absoluteString
        ]
        NSWorkspace.shared.openApplication(
            at: chromeURL,
            configuration: configuration
        )
    }

    func showWindow() {
        if window == nil {
            makeWindow()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.unhide(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func closeWindow() {
        window?.close()
    }

    private func makeWindow() {
        let hostingView = NSHostingView(rootView: BatchTranscriptionView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcription Batch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 680, height: 420)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setFrameAutosaveName("diduny.transcription-batch")
        window.center()

        windowDelegate = BatchTranscriptionWindowDelegate {
            MainWindowController.shared.refreshActivationPolicy()
        }
        window.delegate = windowDelegate
        self.window = window
    }

    private func presentYouTubeURLImporter(startsNewBatch: Bool) {
        showWindow()
        guard urlImportWindow == nil, let window else { return }

        let importView = YouTubeURLImportView(
            onCancel: { [weak self] in self?.dismissYouTubeURLImporter() },
            onSubmit: { [weak self] sources, profileID in
                SettingsStorage.shared.selectedChromeProfileID = profileID
                SettingsStorage.shared.remoteMediaRightsAcknowledged = true
                let service = FileTranscriptionBatchService.shared
                if startsNewBatch {
                    service.beginBatch(remoteSources: sources)
                } else {
                    service.add(remoteSources: sources)
                    service.startIfNeeded()
                }
                self?.dismissYouTubeURLImporter()
            }
        )
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: importView))
        sheet.title = "Transcribe YouTube URLs"
        sheet.styleMask = [.titled, .closable]
        sheet.contentMinSize = NSSize(width: 560, height: 430)
        urlImportWindow = sheet
        window.beginSheet(sheet)
    }

    private func dismissYouTubeURLImporter() {
        guard let sheet = urlImportWindow else { return }
        window?.endSheet(sheet)
        urlImportWindow = nil
    }
}

private final class BatchTranscriptionWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_: Notification) {
        onClose()
    }
}

enum ImportedMediaPicker {
    static let allowedContentTypes: [UTType] = [
        .audio,
        .mpeg4Audio,
        .mp3,
        .wav,
        .aiff,
        UTType("org.xiph.flac") ?? .audio,
        UTType("public.ogg-audio") ?? .audio,
        .mpeg4Movie,
        .movie,
        .video
    ]

    @MainActor
    static func selectFiles() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Select Audio or Video Files to Transcribe"
        panel.prompt = "Transcribe"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedContentTypes

        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.urls : nil
    }
}

private struct BatchTranscriptionView: View {
    @State private var service = FileTranscriptionBatchService.shared
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .background(Color(.windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            let supported = urls.filter { url in
                guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
                    return false
                }
                return ImportedMediaPicker.allowedContentTypes.contains(where: { type.conforms(to: $0) })
            }
            guard !supported.isEmpty else { return false }
            service.add(urls: supported)
            service.startIfNeeded()
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) {
                isDropTargeted = targeted
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: service.items)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcription Batch")
                        .font(.title2.bold())
                    Text(summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    BatchTranscriptionWindowController.shared.addFiles()
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
                .help("Add audio or video files (⌘O)")

                Button {
                    BatchTranscriptionWindowController.shared.addYouTubeURLs()
                } label: {
                    Label("Add URLs", systemImage: "link.badge.plus")
                }
                .keyboardShortcut("u", modifiers: .command)
                .help("Add YouTube URLs (⌘U)")
            }

            if let error = service.batchError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 12))
                    Spacer()
                    if service.isAuthorizationPaused {
                        Menu("Chrome Profile") {
                            ForEach(ChromeProfileStore.discover()) { profile in
                                Button {
                                    SettingsStorage.shared.selectedChromeProfileID = profile.id
                                } label: {
                                    if SettingsStorage.shared.selectedChromeProfileID == profile.id {
                                        Label(profile.name, systemImage: "checkmark")
                                    } else {
                                        Text(profile.name)
                                    }
                                }
                            }
                        }
                        .controlSize(.small)
                        Button("Open YouTube") {
                            BatchTranscriptionWindowController.shared.openYouTubeInSelectedChrome()
                        }
                        .controlSize(.small)
                    }
                    Button("Try Again") {
                        if service.isAuthorizationPaused {
                            service.retryAuthorization()
                        } else {
                            service.startIfNeeded()
                        }
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 38)
        .padding(.bottom, 16)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if service.items.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop audio or video files here")
                    .font(.headline)
                Text("Diduny extracts audio locally before transcription.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Choose Files…") {
                    BatchTranscriptionWindowController.shared.addFiles()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(service.items.enumerated()), id: \.element.id) { index, item in
                        BatchTranscriptionRow(item: item, service: service)
                        if index < service.items.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if service.failedCount > 0, !service.isProcessing {
                Button("Retry Failed") {
                    service.retryFailed()
                }
            }

            if !service.isProcessing, service.finishedCount > 0 {
                Button("Clear Finished") {
                    service.clearFinished()
                }
            }

            Spacer()

            if service.isProcessing {
                Button("Stop Batch", role: .destructive) {
                    service.cancelAll()
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button("Close") {
                    BatchTranscriptionWindowController.shared.closeWindow()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var summaryText: String {
        guard !service.items.isEmpty else { return "No files selected" }
        if service.isProcessing {
            let noun = service.activeCount == 1 ? "file" : "files"
            return "\(service.finishedCount) of \(service.items.count) finished · \(service.activeCount) \(noun) processing"
        }
        if service.failedCount > 0 {
            return "\(service.completedCount) completed · \(service.failedCount) failed"
        }
        if service.duplicateCount > 0 {
            return "\(service.completedCount) available · \(service.duplicateCount) duplicates reused"
        }
        return "\(service.completedCount) of \(service.items.count) completed"
    }
}

private struct YouTubeURLImportView: View {
    let onCancel: () -> Void
    let onSubmit: ([YouTubeRemoteMediaSource], String) -> Void

    private let profiles: [ChromeProfile]
    @State private var rawURLs = ""
    @State private var selectedProfileID: String
    @State private var rightsAcknowledged: Bool
    @State private var validationMessage: String?

    init(
        onCancel: @escaping () -> Void,
        onSubmit: @escaping ([YouTubeRemoteMediaSource], String) -> Void
    ) {
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        let profiles = ChromeProfileStore.discover()
        self.profiles = profiles
        let storedProfile = SettingsStorage.shared.selectedChromeProfileID
        _selectedProfileID = State(
            initialValue: profiles.contains(where: { $0.id == storedProfile })
                ? storedProfile ?? ""
                : profiles.first?.id ?? ""
        )
        _rightsAcknowledged = State(
            initialValue: SettingsStorage.shared.remoteMediaRightsAcknowledged
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcribe YouTube URLs")
                    .font(.title2.bold())
                Text("Add individual videos or Shorts, one URL per line.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $rawURLs)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
                }
                .frame(minHeight: 150)

            VStack(alignment: .leading, spacing: 8) {
                Picker("Chrome profile", selection: $selectedProfileID) {
                    ForEach(profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .disabled(profiles.isEmpty)

                Label(
                    "Chrome keeps your YouTube session. Diduny remembers only the selected profile and never stores Google credentials.",
                    systemImage: "hand.raised"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Button {
                BatchTranscriptionWindowController.shared.openYouTubeInChrome(
                    profileID: selectedProfileID
                )
            } label: {
                Label("Open YouTube in Selected Profile", systemImage: "safari")
            }
            .disabled(selectedProfileID.isEmpty)

            if !SettingsStorage.shared.remoteMediaRightsAcknowledged {
                Toggle(
                    "I own this content or have permission to transcribe it.",
                    isOn: $rightsAcknowledged
                )
                .toggleStyle(.checkbox)
            }

            if profiles.isEmpty {
                Text("No Google Chrome profiles were found. Open Chrome once, then try again.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add to Batch", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        rawURLs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || selectedProfileID.isEmpty
                            || !rightsAcknowledged
                    )
            }
        }
        .padding(20)
        .frame(width: 560, height: 430)
    }

    private func submit() {
        do {
            let sources = try YouTubeRemoteMediaSource.normalizeBatch(rawURLs)
            guard !sources.isEmpty else {
                validationMessage = "Add at least one YouTube video URL."
                return
            }
            validationMessage = nil
            onSubmit(sources, selectedProfileID)
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
