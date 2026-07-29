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

    @Test("Local mode exposes only transcription and meeting capture")
    func localModeHidesCloudActions() {
        let model = EdgeCommandPanelModel(
            pairs: [.defaultPair],
            selectedPair: .defaultPair,
            provider: .local,
            isSignedIn: true
        )

        #expect(model.availableActions == [.transcribe, .meeting])
        #expect(!model.showsTranslationControls)
    }

    @Test("Cloud mode adds translation actions and target language")
    func cloudModeAddsTranslationActions() {
        let model = EdgeCommandPanelModel(
            pairs: [.defaultPair],
            selectedPair: .defaultPair,
            provider: .local,
            isSignedIn: true
        )

        #expect(model.selectProvider(.cloud))
        #expect(model.availableActions == [.transcribe, .translate, .meeting, .translateMeeting])
        #expect(model.showsTranslationControls)
    }

    @Test("Cloud mode requires an authenticated session")
    func signedOutUserCannotSelectCloud() {
        let model = EdgeCommandPanelModel(
            pairs: [.defaultPair],
            selectedPair: .defaultPair,
            provider: .local,
            isSignedIn: false
        )

        #expect(!model.selectProvider(.cloud))
        #expect(model.provider == .local)
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

        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: rightDock, presentation: .collapsed)
            == NSRect(x: 1426, y: 418, width: 14, height: 64))
        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: rightDock, presentation: .commands(isCloud: true))
            == NSRect(x: 1154, y: 287, width: 286, height: 326))
        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: bottomDock, presentation: .collapsed)
            == NSRect(x: 688, y: 0, width: 64, height: 14))
        #expect(EdgeCommandPanelPlacement.frame(in: visibleFrame, dock: bottomDock, presentation: .commands(isCloud: true))
            == NSRect(x: 577, y: 0, width: 286, height: 326))
    }

    @Test("Meeting feedback grows beyond the compact dictation panel")
    func meetingFeedbackUsesLargerScrollableFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let dock = EdgeCommandPanelDock(edge: .right, offset: 450)
        let dictation = EdgeCommandPanelPlacement.frame(
            in: visibleFrame,
            dock: dock,
            presentation: .live(.voice)
        )
        let meeting = EdgeCommandPanelPlacement.frame(
            in: visibleFrame,
            dock: dock,
            presentation: .live(.meeting)
        )

        #expect(dictation == NSRect(x: 1130, y: 295, width: 310, height: 310))
        #expect(meeting == NSRect(x: 1080, y: 240, width: 360, height: 420))
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

@MainActor
struct EdgeCommandPanelLiveTextTests {
    @Test("Meeting translation displays translated tokens instead of source tokens")
    func meetingTranslationPrefersTranslatedTokens() {
        let store = LiveDictationOverlayStore()
        store.reset(mode: .meetingTranslation)

        store.processTokens([
            RealtimeToken(text: "Привіт", isFinal: true, translationStatus: "source"),
            RealtimeToken(text: "Hello", isFinal: true, translationStatus: "translation")
        ])

        #expect(store.visibleText == "Hello")
    }
}
