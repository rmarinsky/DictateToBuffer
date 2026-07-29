import AppKit
import Observation
import SwiftUI

enum EdgeCommandAction: CaseIterable, Identifiable {
    case transcribe
    case translate
    case meeting
    case translateMeeting
    case batch

    var id: Self { self }

    var title: String {
        switch self {
        case .transcribe: "Transcribe"
        case .translate: "Translate"
        case .meeting: "Record meeting"
        case .translateMeeting: "Translate meeting"
        case .batch: "Batch files"
        }
    }

    var icon: String {
        switch self {
        case .transcribe: "waveform"
        case .translate: "character.bubble"
        case .meeting: "record.circle"
        case .translateMeeting: "captions.bubble"
        case .batch: "tray.full"
        }
    }

    var usesLanguagePair: Bool {
        self == .translate || self == .translateMeeting
    }
}

enum EdgeCommandPanelPlacement {
    static func frame(in visibleFrame: NSRect, pinnedOrigin: NSPoint?, expanded: Bool) -> NSRect {
        let width = expanded ? expandedSize.width : handleWidth
        let preferredOrigin = pinnedOrigin ?? NSPoint(
            x: visibleFrame.maxX - width,
            y: visibleFrame.midY - expandedSize.height / 2
        )
        let origin = NSPoint(
            x: min(max(preferredOrigin.x, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(preferredOrigin.y, visibleFrame.minY), visibleFrame.maxY - expandedSize.height)
        )
        return NSRect(origin: origin, size: NSSize(width: width, height: expandedSize.height))
    }

    static let expandedSize = NSSize(width: 304, height: 314)
    static let handleWidth: CGFloat = 14
}

@Observable
@MainActor
final class EdgeCommandPanelModel {
    var pairs: [TranslationLanguagePair]
    var selectedPairID: String

    init(pairs: [TranslationLanguagePair], selectedPair: TranslationLanguagePair) {
        let normalizedPairs = pairs.isEmpty ? [.defaultPair] : pairs
        self.pairs = normalizedPairs
        selectedPairID = normalizedPairs.contains(selectedPair) ? selectedPair.id : normalizedPairs[0].id
    }

    var selectedPair: TranslationLanguagePair? {
        pairs.first(where: { $0.id == selectedPairID }) ?? pairs.first
    }

    func select(_ pair: TranslationLanguagePair) {
        guard pairs.contains(pair) else { return }
        selectedPairID = pair.id
    }

    func refresh(pairs: [TranslationLanguagePair], selectedPair: TranslationLanguagePair) {
        self.pairs = pairs.isEmpty ? [.defaultPair] : pairs
        selectedPairID = self.pairs.contains(selectedPair) ? selectedPair.id : self.pairs[0].id
    }
}

@MainActor
final class EdgeCommandPanelController: NSObject, NSWindowDelegate {
    static let shared = EdgeCommandPanelController()

    private weak var appDelegate: AppDelegate?
    private var panel: EdgeCommandPanel?
    private var model: EdgeCommandPanelModel?
    private var collapseTask: Task<Void, Never>?
    private var compactFeedbackKind: RecordingKind?
    private var pinnedOrigin: NSPoint?
    private var isUserDragging = false

    private override init() {
        super.init()
    }

    func configure(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        refreshModel()
        showCollapsed()
    }

    func usesCompactFeedback(for mode: RecordingMode) -> Bool {
        switch (compactFeedbackKind, mode) {
        case (.voice, .voice), (.translation, .translation), (.meeting, .meeting), (.meetingTranslation, .meetingTranslation):
            true
        default:
            false
        }
    }

    func finishCompactFeedback(for mode: RecordingMode) {
        guard usesCompactFeedback(for: mode) else { return }
        compactFeedbackKind = nil
    }

    private func refreshModel() {
        let pairs = SettingsStorage.shared.translationLanguagePairs
        let selected = SettingsStorage.shared.resolveTranslationLanguagePair()
        if let model {
            model.refresh(pairs: pairs, selectedPair: selected)
        } else {
            model = EdgeCommandPanelModel(pairs: pairs, selectedPair: selected)
        }
    }

    private func showCollapsed() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, expanded: false)
        panel.orderFrontRegardless()
    }

    private func showExpanded() {
        collapseTask?.cancel()
        refreshModel()
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, expanded: true)
        panel.orderFrontRegardless()
    }

    private func setHovering(_ hovering: Bool) {
        if hovering {
            showExpanded()
        } else {
            collapseTask?.cancel()
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self?.showCollapsed()
            }
        }
    }

    private func perform(_ action: EdgeCommandAction) {
        guard let appDelegate else { return }
        let pair = model?.selectedPair

        switch action {
        case .transcribe:
            if appDelegate.appState.recordingState == .idle {
                guard appDelegate.canStartRecording(kind: .voice) else { showCollapsed(); return }
                compactFeedbackKind = .voice
            }
            appDelegate.toggleRecording()
        case .translate:
            if appDelegate.appState.translationRecordingState == .idle {
                guard appDelegate.canStartRecording(kind: .translation), let pair else { showCollapsed(); return }
                compactFeedbackKind = .translation
                Task { await appDelegate.startTranslationRecording(languagePair: pair) }
            } else {
                appDelegate.toggleTranslationRecording()
            }
        case .meeting:
            if appDelegate.appState.meetingRecordingState == .idle {
                guard appDelegate.canStartRecording(kind: .meeting) else { showCollapsed(); return }
                compactFeedbackKind = .meeting
            }
            appDelegate.toggleMeetingRecording()
        case .translateMeeting:
            if appDelegate.appState.meetingTranslationRecordingState == .idle {
                guard appDelegate.canStartRecording(kind: .meetingTranslation), let pair else { showCollapsed(); return }
                compactFeedbackKind = .meetingTranslation
                Task { await appDelegate.startMeetingTranslationRecording(languagePair: pair) }
            } else {
                appDelegate.toggleMeetingTranslationRecording()
            }
        case .batch:
            appDelegate.batchFilesAndURLs()
        }

        showCollapsed()
    }

    private func makePanel() -> EdgeCommandPanel {
        let panel = EdgeCommandPanel(
            contentRect: NSRect(origin: .zero, size: EdgeCommandPanelPlacement.expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: EdgeCommandPanelView(
            model: model!,
            onAction: { [weak self] action in self?.perform(action) },
            onHoverChange: { [weak self] hovering in self?.setHovering(hovering) }
        ))
        return panel
    }

    private func position(_ panel: NSPanel, expanded: Bool) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(
            EdgeCommandPanelPlacement.frame(in: frame, pinnedOrigin: pinnedOrigin, expanded: expanded),
            display: true,
            animate: true
        )
    }

    func windowWillMove(_: Notification) {
        isUserDragging = true
    }

    func windowDidMove(_: Notification) {
        guard isUserDragging, let panel else { return }
        pinnedOrigin = panel.frame.origin
        isUserDragging = false
    }
}

private final class EdgeCommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct EdgeCommandPanelView: View {
    let model: EdgeCommandPanelModel
    let onAction: (EdgeCommandAction) -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("BrandAccentDeep"))
                .frame(width: 8, height: 56)
                .frame(width: 14, height: 314)
                .accessibilityLabel("Open Diduny quick actions")

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .help("Drag to reposition")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diduny")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("Quick actions")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color("BrandAccentDeep"))
                }

                if model.pairs.count > 1 {
                    Picker("Translate to", selection: $model.selectedPairID) {
                        ForEach(model.pairs) { pair in
                            Text(pair.displayLabel).tag(pair.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let pair = model.selectedPair {
                    Label(pair.displayLabel, systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color("BrandAccentDeep"))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(EdgeCommandAction.allCases) { action in
                        Button { onAction(action) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(action.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 47, alignment: .leading)
                            .padding(9)
                            .foregroundStyle(Color.primary)
                            .background(Color("BrandTintSoft"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(actionHelp(action))
                    }
                }
            }
            .padding(14)
            .frame(width: 290, height: 314)
            .background(.regularMaterial, in: UnevenRoundedRectangle(bottomTrailingRadius: 14, topTrailingRadius: 14))
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color("BrandTintBorder").opacity(0.8)).frame(width: 1)
            }
        }
        .frame(width: 304, height: 314)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChange)
    }

    private func actionHelp(_ action: EdgeCommandAction) -> String {
        guard action.usesLanguagePair else { return action.title }
        return "Uses \(model.selectedPair?.displayLabel ?? "the selected language pair")"
    }
}
