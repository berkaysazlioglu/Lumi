import XCTest
@testable import LumiKit

final class PromptInjectionTests: XCTestCase {
    func testWrapsWithBracketedPasteAndSubmits() {
        let encoded = PromptInjection.encode("hello")
        XCTAssertEqual(encoded, "\u{1B}[200~hello\u{1B}[201~\r")
    }

    /// Çok satırlı prompt paste sınırları içinde kalır → erken submit olmaz;
    /// submit yalnız sondaki tek CR ile.
    func testMultilinePromptStaysInsidePasteBounds() {
        let encoded = PromptInjection.encode("line1\nline2")
        XCTAssertEqual(encoded, "\u{1B}[200~line1\nline2\u{1B}[201~\r")
        // Paste-end'den önce CR olmamalı (erken submit yok).
        let beforeEnd = encoded.components(separatedBy: "\u{1B}[201~").first ?? ""
        XCTAssertFalse(beforeEnd.contains("\r"))
    }

    func testTrailingNewlineTrimmedBeforeSubmit() {
        // Kullanıcının sonda bıraktığı newline çift-submit'e yol açmamalı.
        let encoded = PromptInjection.encode("hi\n")
        XCTAssertEqual(encoded, "\u{1B}[200~hi\u{1B}[201~\r")
    }
}
