import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BatchTranscriptionWindowController {
    static let shared = BatchTranscriptionWindowController()

    private var window: NSWindow?
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
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 650),
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
        window.contentMinSize = NSSize(width: 680, height: 520)
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
            }

            if !service.items.isEmpty {
                batchOverview
            }

            if let currentItem = service.currentItem {
                CurrentFileProgressView(
                    item: currentItem,
                    position: currentPosition,
                    totalCount: service.items.count
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let error = service.batchError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 12))
                    Spacer()
                    Button("Try Again") {
                        service.startIfNeeded()
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

    private var batchOverview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Overall progress")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(service.finishedCount) of \(service.items.count) files")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(BatchProgressFormatter.percent(service.progress))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 38, alignment: .trailing)
            }
            ProgressView(value: service.progress)
                .progressViewStyle(.linear)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
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
                Text("Diduny extracts audio locally and transcribes files one at a time.")
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
            return "\(service.finishedCount) of \(service.items.count) finished · processing sequentially"
        }
        if service.failedCount > 0 {
            return "\(service.completedCount) completed · \(service.failedCount) failed"
        }
        return "\(service.completedCount) of \(service.items.count) completed"
    }

    private var currentPosition: Int {
        guard let currentItemID = service.currentItemID,
              let index = service.items.firstIndex(where: { $0.id == currentItemID })
        else { return 0 }
        return index + 1
    }
}
