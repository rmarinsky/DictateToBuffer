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
}
