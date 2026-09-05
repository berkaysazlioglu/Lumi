import CoreGraphics
import Foundation
import XCTest
import LumiKit
@testable import LumiUI

/// `MarkdownDiffView` satır biçimlendirmesinin SAF kuralları (refactor plan 2.8):
/// fence etiketi, başlık boyut merdiveni, diff gutter etiketi.
final class MarkdownRowFormattingTests: XCTestCase {
    // MARK: - fenceLabel

    func testFenceLabelExtractsLanguage() {
        XCTAssertEqual(MarkdownRowFormatting.fenceLabel("```swift"), "swift")
        XCTAssertEqual(MarkdownRowFormatting.fenceLabel("~~~python"), "python")
    }

    func testFenceLabelLowercasesAndTrims() {
        XCTAssertEqual(MarkdownRowFormatting.fenceLabel("```  TypeScript  "), "typescript")
    }

    func testBareFenceGetsEllipsisMarker() {
        XCTAssertEqual(MarkdownRowFormatting.fenceLabel("```"), "···")
        XCTAssertEqual(MarkdownRowFormatting.fenceLabel("~~~   "), "···")
        XCTAssertEqual(MarkdownRowFormatting.fenceLabel(""), "···")
    }

    func testOnlyLeadingFenceCharactersAreStripped() {
        // `drop(while:)` yalnız BAŞTAN atar — dil adının içindeki tırnak kalır.
        XCTAssertEqual(MarkdownRowFormatting.fenceLabel("```js`x"), "js`x")
    }

    // MARK: - headingSize

    func testHeadingSizeLadderIsMonotonic() {
        // Faz 7.1 ikinci dalga: `fontSize + 7/4/2/1` aritmetiği yerine ölçek
        // basamağı. 13pt tabanda merdiven 20/18/15/13 (v1: 20/17/15/14).
        let base = Theme.Typography.Size.base
        let sizes = (1 ... 6).map { MarkdownRowFormatting.headingSize($0, base: base) }
        XCTAssertEqual(sizes[0], .heading)
        XCTAssertEqual(sizes[1], .headline)
        XCTAssertEqual(sizes[2], .title)
        XCTAssertEqual(sizes[3], base, "h4+ tek bir taban boyutu paylaşır")
        XCTAssertEqual(sizes[4], base)
        XCTAssertEqual(sizes[5], base)
        XCTAssertEqual(sizes, sizes.sorted(by: >), "h1 en büyük, aşağı doğru küçülür")
    }

    func testHeadingSizeIsRelativeToTheGivenBase() {
        // Taban değişince merdiven ölçeğin İÇİNDE kayar, ölçek dışına taşmaz.
        XCTAssertEqual(MarkdownRowFormatting.headingSize(1, base: .body), .headline)
        XCTAssertEqual(
            MarkdownRowFormatting.headingSize(0, base: .body), .body,
            "geçersiz level default dala düşer"
        )
    }

    func testHeadingSizeClampsAtTheTopOfTheScale() {
        // Ölçeğin tepesinde +3 basamak yoktur; kırpılır, taşmaz.
        XCTAssertEqual(MarkdownRowFormatting.headingSize(1, base: .splash), .splash)
    }

    // MARK: - gutterLabel

    private func line(
        kind: DiffLine.Kind,
        old: Int?,
        new: Int?
    ) -> MarkdownDiffBuilder.Line {
        MarkdownDiffBuilder.Line(
            kind: kind,
            oldLineNumber: old,
            newLineNumber: new,
            style: .paragraph,
            content: "text"
        )
    }

    func testAdditionUsesNewNumberWithPlus() {
        XCTAssertEqual(MarkdownRowFormatting.gutterLabel(line(kind: .addition, old: nil, new: 12)), "12 +")
    }

    func testDeletionUsesOldNumberWithMinusSign() {
        // Not: ASCII "-" değil U+2212 MINUS SIGN.
        XCTAssertEqual(MarkdownRowFormatting.gutterLabel(line(kind: .deletion, old: 9, new: nil)), "9 −")
    }

    func testContextShowsBareNumber() {
        XCTAssertEqual(MarkdownRowFormatting.gutterLabel(line(kind: .context, old: 4, new: 7)), "7")
    }

    func testNewNumberWinsOverOldWhenBothPresent() {
        XCTAssertEqual(MarkdownRowFormatting.gutterLabel(line(kind: .addition, old: 3, new: 8)), "8 +")
    }

    func testMissingNumbersLeaveOnlyTheMarker() {
        XCTAssertEqual(MarkdownRowFormatting.gutterLabel(line(kind: .addition, old: nil, new: nil)), " +")
        XCTAssertEqual(MarkdownRowFormatting.gutterLabel(line(kind: .context, old: nil, new: nil)), "")
    }
}
