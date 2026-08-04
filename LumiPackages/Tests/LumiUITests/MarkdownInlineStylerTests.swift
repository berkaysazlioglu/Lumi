import SwiftUI
import XCTest
@testable import LumiUI

/// Satır-içi stillendirme (karar 21): kod/link run'ları tema attribute'larını
/// alır ve metin bozulmaz (run range'leri mutasyon sırasında geçerli kalır).
final class MarkdownInlineStylerTests: XCTestCase {
    func testCodeRunsGetMonospacedFontAndAccentColor() {
        let styled = MarkdownInlineStyler.styled("çalıştır: `swift build` sonra dene", fontSize: 13)

        XCTAssertEqual(String(styled.characters), "çalıştır: swift build sonra dene")
        let codeRun = styled.runs.first { $0.inlinePresentationIntent?.contains(.code) == true }
        let range = try? XCTUnwrap(codeRun?.range)
        XCTAssertNotNil(range)
        XCTAssertEqual(styled[range!].foregroundColor, Theme.accentCyan)
        XCTAssertEqual(styled[range!].font, .system(size: 12, design: .monospaced))
    }

    func testLinkRunsGetAccentColorAndUnderline() {
        let styled = MarkdownInlineStyler.styled("[tasarım](docs/design.md)", fontSize: 13)

        let linkRun = styled.runs.first { $0.link != nil }
        let range = try? XCTUnwrap(linkRun?.range)
        XCTAssertNotNil(range)
        XCTAssertEqual(styled[range!].foregroundColor, Theme.accentPrimary)
        XCTAssertEqual(styled[range!].underlineStyle, .single)
    }

    func testMultipleCodeRunsAreAllStyled() {
        let styled = MarkdownInlineStyler.styled("`a` ve `b` ve `c`", fontSize: 13)

        let codeRuns = styled.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }
        XCTAssertEqual(codeRuns.count, 3)
        XCTAssertTrue(codeRuns.allSatisfy { styled[$0.range].foregroundColor == Theme.accentCyan })
        XCTAssertEqual(String(styled.characters), "a ve b ve c")
    }

    func testPlainTextIsUnchanged() {
        let styled = MarkdownInlineStyler.styled("düz metin", fontSize: 13)

        XCTAssertEqual(String(styled.characters), "düz metin")
        XCTAssertNil(styled.runs.first?.foregroundColor)
    }
}
