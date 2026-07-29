import AppKit
import Observation
import QuartzCore
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

enum EdgeCommandPanelDockEdge: Equatable {
    case left
    case right
    case top
    case bottom
}

struct EdgeCommandPanelDock: Equatable {
    let edge: EdgeCommandPanelDockEdge
    let offset: CGFloat
}

enum EdgeCommandPanelPlacement {
    static func nearestDock(to proposedFrame: NSRect, in visibleFrame: NSRect) -> EdgeCommandPanelDock {
        let distances: [(EdgeCommandPanelDockEdge, CGFloat)] = [
            (.left, abs(proposedFrame.minX - visibleFrame.minX)),
            (.right, abs(visibleFrame.maxX - proposedFrame.maxX)),
            (.bottom, abs(proposedFrame.minY - visibleFrame.minY)),
            (.top, abs(visibleFrame.maxY - proposedFrame.maxY))
        ]
        let edge = distances.min(by: { $0.1 < $1.1 })?.0 ?? .right
        let offset = edge == .left || edge == .right ? proposedFrame.midY : proposedFrame.midX
        return EdgeCommandPanelDock(edge: edge, offset: offset)
    }

    static func frame(in visibleFrame: NSRect, dock: EdgeCommandPanelDock, expanded: Bool) -> NSRect {
        let size = expanded ? expandedSize : collapsedSize(for: dock.edge)
        let origin: NSPoint

        switch dock.edge {
        case .left:
            origin = NSPoint(
                x: visibleFrame.minX,
                y: clampedOrigin(dock.offset, length: size.height, minimum: visibleFrame.minY, maximum: visibleFrame.maxY)
            )
        case .right:
            origin = NSPoint(
                x: visibleFrame.maxX - size.width,
                y: clampedOrigin(dock.offset, length: size.height, minimum: visibleFrame.minY, maximum: visibleFrame.maxY)
            )
        case .top:
            origin = NSPoint(
                x: clampedOrigin(dock.offset, length: size.width, minimum: visibleFrame.minX, maximum: visibleFrame.maxX),
                y: visibleFrame.maxY - size.height
            )
        case .bottom:
            origin = NSPoint(
                x: clampedOrigin(dock.offset, length: size.width, minimum: visibleFrame.minX, maximum: visibleFrame.maxX),
                y: visibleFrame.minY
            )
        }

        return NSRect(origin: origin, size: size)
    }

    static let expandedSize = NSSize(width: 286, height: 326)

    private static func collapsedSize(for edge: EdgeCommandPanelDockEdge) -> NSSize {
        switch edge {
        case .left, .right: NSSize(width: 14, height: 64)
        case .top, .bottom: NSSize(width: 64, height: 14)
        }
    }

    private static func clampedOrigin(_ offset: CGFloat, length: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(offset - length / 2, minimum), maximum - length)
    }
}

enum EdgeCommandPanelHoverPolicy {
    static func shouldCollapse(pointer: NSPoint, panelFrame: NSRect, isDragging: Bool) -> Bool {
        !isDragging && !panelFrame.contains(pointer)
    }
}

@Observable
@MainActor
final class EdgeCommandPanelModel {
    var pairs: [TranslationLanguagePair]
    var selectedPairID: String
    var isExpanded = false
    var dockEdge: EdgeCommandPanelDockEdge = .right

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
final class EdgeCommandPanelController: NSObject {
    static let shared = EdgeCommandPanelController()

    private weak var appDelegate: AppDelegate?
    private var panel: EdgeCommandPanel?
    private var panelContentView: EdgeCommandPanelContentView?
    private var model: EdgeCommandPanelModel?
    private var collapseTask: Task<Void, Never>?
    private var compactFeedbackKind: RecordingKind?
    private var dock: EdgeCommandPanelDock?
    private var dragCursorOffset: NSPoint?

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
        collapseTask?.cancel()
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
            collapseTask?.cancel()
            guard model?.isExpanded != true else { return }
            showExpanded()
        } else {
            guard model?.isExpanded == true else { return }
            collapseTask?.cancel()
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self, let panel = self.panel else { return }
                guard EdgeCommandPanelHoverPolicy.shouldCollapse(
                    pointer: NSEvent.mouseLocation,
                    panelFrame: panel.frame,
                    isDragging: self.dragCursorOffset != nil
                ) else { return }
                self.showCollapsed()
            }
        }
    }

    private func dragPanel() {
        guard let panel else { return }
        collapseTask?.cancel()
        let cursor = NSEvent.mouseLocation
        if dragCursorOffset == nil {
            dragCursorOffset = NSPoint(x: cursor.x - panel.frame.minX, y: cursor.y - panel.frame.minY)
        }
        guard let dragCursorOffset else { return }
        panel.setFrameOrigin(NSPoint(x: cursor.x - dragCursorOffset.x, y: cursor.y - dragCursorOffset.y))
    }

    private func finishDraggingPanel() {
        guard let panel, dragCursorOffset != nil else { return }
        dragCursorOffset = nil
        let screen = activeScreen() ?? panel.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        dock = EdgeCommandPanelPlacement.nearestDock(to: panel.frame, in: visibleFrame)
        model?.dockEdge = dock?.edge ?? .right
        position(panel, expanded: true, on: visibleFrame)
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
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true

        let tabView = EdgeCommandTabView(
            model: model!,
            onExpand: { [weak self] in self?.showExpanded() },
            onDrag: { [weak self] in self?.dragPanel() },
            onDragEnd: { [weak self] in self?.finishDraggingPanel() }
        )
        let expandedView = EdgeCommandExpandedView(
            model: model!,
            onAction: { [weak self] action in self?.perform(action) },
            onCollapse: { [weak self] in self?.showCollapsed() },
            onDrag: { [weak self] in self?.dragPanel() },
            onDragEnd: { [weak self] in self?.finishDraggingPanel() }
        )
        let contentView = EdgeCommandPanelContentView(
            tabView: tabView,
            expandedView: expandedView,
            onHoverChange: { [weak self] hovering in self?.setHovering(hovering) }
        )
        panelContentView = contentView
        panel.contentView = contentView
        return panel
    }

    private func position(_ panel: NSPanel, expanded: Bool, on explicitVisibleFrame: NSRect? = nil) {
        let screen = dock == nil ? activeScreen() : panel.screen ?? activeScreen()
        let visibleFrame = explicitVisibleFrame
            ?? screen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let resolvedDock = dock ?? EdgeCommandPanelDock(edge: .right, offset: visibleFrame.midY)
        dock = resolvedDock
        model?.dockEdge = resolvedDock.edge
        model?.isExpanded = expanded
        panelContentView?.setExpanded(expanded)

        let frame = EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: resolvedDock, expanded: expanded)
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func activeScreen() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }
}

private final class EdgeCommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class EdgeCommandPanelContentView: NSView {
    private let tabHostingView: NSHostingView<EdgeCommandTabView>
    private let expandedHostingView: NSHostingView<EdgeCommandExpandedView>
    private let onHoverChange: (Bool) -> Void
    private var hoverTrackingArea: NSTrackingArea?

    init(
        tabView: EdgeCommandTabView,
        expandedView: EdgeCommandExpandedView,
        onHoverChange: @escaping (Bool) -> Void
    ) {
        tabHostingView = NSHostingView(rootView: tabView)
        expandedHostingView = NSHostingView(rootView: expandedView)
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)

        tabHostingView.sizingOptions = []
        expandedHostingView.sizingOptions = []
        for hostingView: NSView in [tabHostingView, expandedHostingView] {
            hostingView.autoresizingMask = [.width, .height]
            addSubview(hostingView)
        }
        setExpanded(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        tabHostingView.frame = bounds
        expandedHostingView.frame = bounds
    }

    func setExpanded(_ expanded: Bool) {
        tabHostingView.isHidden = expanded
        expandedHostingView.isHidden = !expanded
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange(false)
    }
}

private struct EdgeCommandTabView: View {
    let model: EdgeCommandPanelModel
    let onExpand: () -> Void
    let onDrag: () -> Void
    let onDragEnd: () -> Void

    var body: some View {
        let edge = model.dockEdge
        Button(action: onExpand) {
            ZStack {
                tabShape
                    .fill(.regularMaterial)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color("BrandAccentDeep"), Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(
                        width: edge == .left || edge == .right ? 3 : 24,
                        height: edge == .left || edge == .right ? 24 : 3
                    )
                    .shadow(color: Color("BrandAccentDeep").opacity(0.45), radius: 5)
            }
            .overlay(tabShape.stroke(Color("BrandTintBorder"), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gesture(dragGesture)
        .accessibilityLabel("Open Diduny quick actions")
    }

    private var tabShape: UnevenRoundedRectangle {
        switch model.dockEdge {
        case .left:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 10,
                topTrailingRadius: 10
            )
        case .right:
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        case .top:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 10,
                topTrailingRadius: 0
            )
        case .bottom:
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            )
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in onDrag() }
            .onEnded { _ in onDragEnd() }
    }
}

private struct EdgeCommandExpandedView: View {
    let model: EdgeCommandPanelModel
    let onAction: (EdgeCommandAction) -> Void
    let onCollapse: () -> Void
    let onDrag: () -> Void
    let onDragEnd: () -> Void

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            header

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(EdgeCommandAction.allCases.filter { $0 != .batch }) { action in
                    EdgeCommandActionButton(
                        action: action,
                        meta: actionMeta(action),
                        onAction: { onAction(action) }
                    )
                }
            }

            HStack(spacing: 8) {
                Text("Translate to")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Picker("Translate to", selection: $model.selectedPairID) {
                    ForEach(model.pairs) { pair in
                        Text(languageName(pair.languageB)).tag(pair.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }

            Button { onAction(.batch) } label: {
                Label("Batch files & URLs", systemImage: EdgeCommandAction.batch.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.plain)
            .help("Process multiple files and URLs")
        }
        .padding(14)
        .background(.regularMaterial, in: panelShape)
        .overlay(panelShape.stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
    }

    private var header: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.pink, Color("BrandAccentDeep")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color("BrandAccentDeep").opacity(0.28), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("Diduny")
                    .font(.system(size: 13, weight: .bold))
                Text("What do you want to capture?")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: onCollapse) {
                Image(systemName: collapseSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Hide quick actions")
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .help("Drag to attach to another screen edge")
    }

    private var panelShape: UnevenRoundedRectangle {
        switch model.dockEdge {
        case .left:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 15,
                topTrailingRadius: 15
            )
        case .right:
            UnevenRoundedRectangle(
                topLeadingRadius: 15,
                bottomLeadingRadius: 15,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        case .top:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 15,
                bottomTrailingRadius: 15,
                topTrailingRadius: 0
            )
        case .bottom:
            UnevenRoundedRectangle(
                topLeadingRadius: 15,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 15
            )
        }
    }

    private var collapseSymbol: String {
        switch model.dockEdge {
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .top: "chevron.up"
        case .bottom: "chevron.down"
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in onDrag() }
            .onEnded { _ in onDragEnd() }
    }

    private func actionMeta(_ action: EdgeCommandAction) -> String {
        switch action {
        case .transcribe: "Voice → text"
        case .translate: "Voice → \(targetCode)"
        case .meeting: "System + mic"
        case .translateMeeting: "Live → \(targetCode)"
        case .batch: ""
        }
    }

    private var targetCode: String {
        model.selectedPair?.languageB.uppercased() ?? "EN"
    }

    private func languageName(_ code: String) -> String {
        SupportedLanguage.language(for: code)?.name ?? code.uppercased()
    }
}

private struct EdgeCommandActionButton: View {
    let action: EdgeCommandAction
    let meta: String
    let onAction: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let highlighted = isHovered || isFocused
        Button(action: onAction) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: action.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color("BrandAccentDeep"))
                    .frame(width: 28, height: 28)
                    .background(Color("BrandTintSoft"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(action.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text(meta)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .background(
            highlighted ? Color("BrandAccentDeep").opacity(0.11) : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(highlighted ? Color("BrandTintBorder") : Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .offset(y: highlighted ? -1 : 0)
        .shadow(color: highlighted ? Color("BrandAccentDeep").opacity(0.14) : .clear, radius: 8, y: 4)
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .onHover { isHovered = $0 }
        .help(action.usesLanguagePair ? "Uses the selected translation language" : action.title)
    }
}
