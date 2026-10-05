import AppKit
import XCTest
@testable import LumiUI

/// Karar 113: yazarken gelen vurgu yalnız değişen run'lara uygulanır — tüm
/// metni yeniden boyamak her tuşta bütün yerleşimi geçersizliyordu.
@MainActor
final class HighlightPatchTests: XCTestCase {
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private func styled(_ parts: [(String, NSColor)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (text, color) in parts {
            result.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        return result
    }

    func testIdenticalHighlightProducesNoChanges() {
        let text = styled([("let ", .systemPurple), ("a = 1", .white)])
        XCTAssertTrue(HighlightPatch.changedRuns(from: text, to: text.copy() as! NSAttributedString).isEmpty)
    }

    func testOnlyTheRecoloredRunIsReported() {
        let current = styled([("let ", .systemPurple), ("a = \"x", .white), ("\n// c", .gray)])
        let target = styled([("let ", .systemPurple), ("a = ", .white), ("\"x", .systemGreen), ("\n// c", .gray)])

        let changes = HighlightPatch.changedRuns(from: current, to: target)

        XCTAssertEqual(changes.map(\.range), [NSRange(location: 8, length: 2)])
    }

    func testRunSplitInsideOneExistingRunIsReported() {
        let current = styled([("abcdef", .white)])
        let target = styled([("abc", .white), ("def", .systemRed)])
        XCTAssertEqual(HighlightPatch.changedRuns(from: current, to: target).map(\.range), [NSRange(location: 3, length: 3)])
    }
}
