import Foundation
import XCTest
@testable import LumiKit

/// `TerminalMeta.displayTitle` — kart header'ı, maximize header'ı, chip şeridi
/// ve session listesinin PAYLAŞTIĞI başlık türevi (refactor 6.7; önceden aynı
/// `oscTitle ?? task ?? name` ifadesi 5 view'da kopyaydı).
final class TerminalMetaTests: XCTestCase {
    private func meta(
        name: String = "term-1",
        task: String? = nil,
        oscTitle: String? = nil
    ) -> TerminalMeta {
        TerminalMeta(
            id: TerminalID(),
            name: name,
            repoPath: "/tmp/repo",
            createdAt: Date(timeIntervalSince1970: 0),
            task: task,
            oscTitle: oscTitle
        )
    }

    func testOSCTitleWinsOverEverything() {
        XCTAssertEqual(
            meta(name: "term-1", task: "Bash", oscTitle: "claude").displayTitle,
            "claude"
        )
    }

    func testTaskUsedWhenNoOSCTitle() {
        XCTAssertEqual(meta(name: "term-1", task: "Bash").displayTitle, "Bash")
    }

    func testNameIsFinalFallback() {
        XCTAssertEqual(meta(name: "term-1").displayTitle, "term-1")
    }

    func testEmptyOSCTitleIsNotTreatedAsMissing() {
        // Boş string nil DEĞİLDİR: emülatör başlığı temizlerse görünen de boşalır
        // (bugünkü `??` zinciriyle birebir aynı davranış).
        XCTAssertEqual(meta(name: "term-1", task: "Bash", oscTitle: "").displayTitle, "")
    }
}
