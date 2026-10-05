import XCTest
@testable import LumiMobileKit

final class PromptDraftTests: XCTestCase {
    func testMultiSelectTogglesAndKeepsOrder() {
        var d = PromptDraft()
        d = d.toggling(question: 0, option: 2, multiSelect: true)
        d = d.toggling(question: 0, option: 0, multiSelect: true)
        XCTAssertEqual(d.selections[0], [2, 0])
        d = d.toggling(question: 0, option: 2, multiSelect: true)
        XCTAssertEqual(d.selections[0], [0])
        XCTAssertTrue(d.isSelected(question: 0, option: 0))
        XCTAssertFalse(d.isSelected(question: 0, option: 2))
    }

    func testSingleSelectReplaces() {
        var d = PromptDraft()
        d = d.toggling(question: 1, option: 0, multiSelect: false)
        d = d.toggling(question: 1, option: 3, multiSelect: false)
        XCTAssertEqual(d.selections[1], [3])
    }

    func testQuestionsAreIndependent() {
        let d = PromptDraft()
            .toggling(question: 0, option: 1, multiSelect: false)
            .toggling(question: 1, option: 1, multiSelect: true)
            .withText("hi", question: 1)
        XCTAssertEqual(d.selections[0], [1])
        XCTAssertEqual(d.selections[1], [1])
        XCTAssertEqual(d.texts[1], "hi")
        XCTAssertNil(d.texts[0])
    }
}
