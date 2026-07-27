import XCTest
@testable import Diduny

@MainActor
final class TranslationPairPickerControllerTests: XCTestCase {
    func testPickShowsPickerForConfiguredPairs() async {
        let pairs = [
            TranslationLanguagePair(languageA: "uk", languageB: "en"),
            TranslationLanguagePair(languageA: "en", languageB: "es"),
        ]

        let selection = Task {
            await TranslationPairPickerController.shared.pick(
                pairs: pairs,
                preselected: pairs[0]
            )
        }
        await Task.yield()

        XCTAssertTrue(TranslationPairPickerController.shared.isVisible)
        TranslationPairPickerController.shared.confirmCurrentSelection()
        let selectedPair = await selection.value
        XCTAssertEqual(selectedPair, pairs[0])
    }
}
