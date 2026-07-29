import AppKit
import Testing
@testable import Diduny

@MainActor
struct EdgeCommandPanelModelTests {
    @Test("Translation actions use the language pair selected in the edge panel")
    func selectedPairDrivesTranslationActions() {
        let english = TranslationLanguagePair(languageA: "uk", languageB: "en")
        let polish = TranslationLanguagePair(languageA: "uk", languageB: "pl")
        let model = EdgeCommandPanelModel(pairs: [english, polish], selectedPair: english)

        model.select(polish)

        #expect(model.selectedPair == polish)
        #expect(EdgeCommandAction.translate.usesLanguagePair)
        #expect(EdgeCommandAction.translateMeeting.usesLanguagePair)
        #expect(!EdgeCommandAction.transcribe.usesLanguagePair)
    }

    @Test("Refreshing configured pairs keeps a valid selected target")
    func refreshReplacesPairsWithoutLeavingAStaleSelection() {
        let english = TranslationLanguagePair(languageA: "uk", languageB: "en")
        let polish = TranslationLanguagePair(languageA: "uk", languageB: "pl")
        let model = EdgeCommandPanelModel(pairs: [english], selectedPair: english)

        model.refresh(pairs: [polish], selectedPair: polish)

        #expect(model.pairs == [polish])
        #expect(model.selectedPair == polish)
    }

    @Test("A dragged panel snaps to the nearest screen edge")
    func draggedPanelSnapsToNearestEdge() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

        #expect(EdgeCommandPanelPlacement.nearestDock(
            to: NSRect(x: 8, y: 260, width: 286, height: 326),
            in: visibleFrame
        ).edge == .left)
        #expect(EdgeCommandPanelPlacement.nearestDock(
            to: NSRect(x: 1140, y: 260, width: 286, height: 326),
            in: visibleFrame
        ).edge == .right)
        #expect(EdgeCommandPanelPlacement.nearestDock(
            to: NSRect(x: 560, y: 8, width: 286, height: 326),
            in: visibleFrame
        ).edge == .bottom)
        #expect(EdgeCommandPanelPlacement.nearestDock(
            to: NSRect(x: 560, y: 566, width: 286, height: 326),
            in: visibleFrame
        ).edge == .top)
    }

    @Test("A docked panel opens inward and collapses to a small edge tab")
    func dockedPanelUsesEdgeAwareFrames() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rightDock = EdgeCommandPanelDock(edge: .right, offset: 450)
        let bottomDock = EdgeCommandPanelDock(edge: .bottom, offset: 720)

        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: rightDock, expanded: false)
            == NSRect(x: 1426, y: 418, width: 14, height: 64))
        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: rightDock, expanded: true)
            == NSRect(x: 1154, y: 287, width: 286, height: 326))
        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: bottomDock, expanded: false)
            == NSRect(x: 688, y: 0, width: 64, height: 14))
        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: bottomDock, expanded: true)
            == NSRect(x: 577, y: 0, width: 286, height: 326))
    }

    @Test("Auto-hide only collapses after the pointer leaves the panel")
    func autoHideChecksThePointerAtTheEndOfTheDelay() {
        let panelFrame = NSRect(x: 1154, y: 287, width: 286, height: 326)

        #expect(!EdgeCommandPanelHoverPolicy.shouldCollapse(
            pointer: NSPoint(x: 1200, y: 400),
            panelFrame: panelFrame,
            isDragging: false
        ))
        #expect(!EdgeCommandPanelHoverPolicy.shouldCollapse(
            pointer: NSPoint(x: 900, y: 400),
            panelFrame: panelFrame,
            isDragging: true
        ))
        #expect(EdgeCommandPanelHoverPolicy.shouldCollapse(
            pointer: NSPoint(x: 900, y: 400),
            panelFrame: panelFrame,
            isDragging: false
        ))
    }
}
