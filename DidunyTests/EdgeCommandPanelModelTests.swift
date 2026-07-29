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

    @Test("A dragged panel collapses to its dropped location")
    func pinnedPanelKeepsItsHandleAtTheDroppedLocation() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let droppedOrigin = NSPoint(x: 400, y: 250)

        let collapsed = EdgeCommandPanelPlacement.frame(
            in: visibleFrame,
            pinnedOrigin: droppedOrigin,
            expanded: false
        )
        let expanded = EdgeCommandPanelPlacement.frame(
            in: visibleFrame,
            pinnedOrigin: droppedOrigin,
            expanded: true
        )

        #expect(collapsed == NSRect(x: 400, y: 250, width: 14, height: 314))
        #expect(expanded == NSRect(x: 400, y: 250, width: 304, height: 314))
    }
}
