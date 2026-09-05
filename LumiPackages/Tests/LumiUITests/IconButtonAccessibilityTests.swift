import Foundation
import XCTest
@testable import LumiUI

/// `IconButton`'ın erişilebilirlik sözleşmesi (Faz 7.6).
///
/// Kural `precondition` değil, saf bir doğrulayıcı + kaynak taraması olarak
/// yaşar: crash yerine **testte** yakalanır ve tüm çağrı yerlerini kapsar.
final class IconButtonAccessibilityTests: XCTestCase {
    // MARK: - Doğrulayıcı

    func testEmptyLabelIsRejected() {
        XCTAssertFalse(IconButtonLabel.isValid(""))
    }

    func testWhitespaceOnlyLabelIsRejected() {
        XCTAssertFalse(IconButtonLabel.isValid("   "))
        XCTAssertFalse(IconButtonLabel.isValid("\n\t "))
    }

    func testMeaningfulLabelIsAccepted() {
        XCTAssertTrue(IconButtonLabel.isValid("Close settings"))
    }

    func testResolveTrimsSurroundingWhitespace() {
        XCTAssertEqual(IconButtonLabel.resolve("  Close  "), "Close")
    }

    func testResolveFallsBackToVisiblePlaceholder() {
        // Sessizce etiketsiz kalmaktansa VoiceOver'da fark edilsin.
        XCTAssertEqual(IconButtonLabel.resolve(" "), "Unlabeled button")
    }

    // MARK: - Çağrı yerleri

    /// Kaynakta `label: ""` (ya da yalnız boşluk) ile kurulmuş bir
    /// `IconButton` olamaz.
    func testNoCallSitePassesAnEmptyLabel() throws {
        let regex = try NSRegularExpression(pattern: #"label:\s*"\s*""#)
        var offenders: [String] = []
        for url in try swiftFiles() {
            let text = try String(contentsOf: url, encoding: .utf8)
            let matches = regex.numberOfMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text)
            )
            if matches > 0 { offenders.append(url.lastPathComponent) }
        }
        XCTAssertEqual(offenders, [], "Boş erişilebilirlik etiketi taşıyan çağrı yeri var")
    }

    /// Hover state'i modülde TEK yerde tutulur: `HoverReader` /
    /// `HoverButtonStyle`. Faz 7'nin ikinci dalgasından sonra istisna yok —
    /// tarama `Sources/LumiUI`'ın tamamını kapsar.
    func testNoFileKeepsPrivateHoverState() throws {
        let regex = try NSRegularExpression(pattern: #"@State\s+private\s+var\s+is\w*Hover"#)
        // HoverReader/HoverButtonStyle hover'ı TUTAN tek yerdir.
        let allowed = ["HoverButtonStyle.swift"]
        var offenders: [String] = []
        for url in try swiftFiles() where !allowed.contains(url.lastPathComponent) {
            // Yorum satırları sayılmaz (dokümantasyonda kalıbın adı geçebilir).
            let code = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let matches = regex.numberOfMatches(
                in: code,
                range: NSRange(code.startIndex..., in: code)
            )
            if matches > 0 { offenders.append(url.lastPathComponent) }
        }
        XCTAssertEqual(offenders, [], "Hover state kopyası kaldı — HoverReader/HoverButtonStyle kullan")
    }

    private func swiftFiles() throws -> [URL] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LumiUI")
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
