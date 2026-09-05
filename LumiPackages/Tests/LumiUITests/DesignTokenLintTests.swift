import Foundation
import XCTest
@testable import LumiUI

/// Token disiplininin kaynak-üstü kapısı (Faz 7.1).
///
/// Faz 7'nin ikinci dalgasında göç TAMAMLANDI: modülde artık tek bir literal
/// punto ya da köşe yarıçapı yok. Eşikler bu yüzden bir "bütçe" değil,
/// **sıfır**: yeni bir `.font(.system(size: …))` ya da `cornerRadius: 12`
/// eklenirse test kırmızıya döner ve `Theme.Typography` / `Theme.Radius`
/// kullanılması gerektiğini söyler.
final class DesignTokenLintTests: XCTestCase {
    /// `Sources/LumiUI` dizini — testin kendi konumundan türetilir.
    private static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)        // Tests/LumiUITests/DesignTokenLintTests.swift
            .deletingLastPathComponent()       // Tests/LumiUITests
            .deletingLastPathComponent()       // Tests
            .deletingLastPathComponent()       // LumiPackages
            .appendingPathComponent("Sources/LumiUI")
    }

    /// `.font(.system(size: …))` — göç tamamlandı, kalan sayı sıfır.
    private static let fontLiteralBudget = 0

    /// `cornerRadius: <sayı>` — göç tamamlandı, kalan sayı sıfır.
    private static let radiusLiteralBudget = 0

    private static let fontLiteral = try! NSRegularExpression(
        pattern: #"\.font\(\.system\(size:"#
    )
    private static let radiusLiteral = try! NSRegularExpression(
        pattern: #"cornerRadius:\s*\(?[0-9]"#
    )

    // MARK: - Testler

    func testModuleContainsNoFontSizeLiterals() throws {
        XCTAssertEqual(
            try scan(Self.fontLiteral), [:],
            "Literal punto kaldı — Theme.Typography kullan"
        )
    }

    func testModuleContainsNoCornerRadiusLiterals() throws {
        XCTAssertEqual(
            try scan(Self.radiusLiteral), [:],
            "Literal köşe yarıçapı kaldı — Theme.Radius kullan"
        )
    }

    func testFontSizeLiteralBudgetIsZero() throws {
        let total = try scan(Self.fontLiteral).values.reduce(0, +)
        XCTAssertEqual(
            total, Self.fontLiteralBudget,
            "Yeni literal punto eklendi; Theme.Typography kullan"
        )
    }

    func testCornerRadiusLiteralBudgetIsZero() throws {
        let total = try scan(Self.radiusLiteral).values.reduce(0, +)
        XCTAssertEqual(
            total, Self.radiusLiteralBudget,
            "Yeni literal köşe yarıçapı eklendi; Theme.Radius kullan"
        )
    }

    // MARK: - Yardımcı

    /// Dosya adı → eşleşme sayısı (yalnız eşleşen dosyalar).
    private func scan(_ regex: NSRegularExpression) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for url in try Self.swiftFiles() {
            // Token tanımlarının kendisi (Theme+Typography) sayılmaz.
            guard url.lastPathComponent != "Theme+Typography.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let matches = regex.numberOfMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text)
            )
            if matches > 0 { counts[url.lastPathComponent] = matches }
        }
        return counts
    }

    private static func swiftFiles() throws -> [URL] {
        let directory = sourceDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            throw LintError.sourceDirectoryMissing(directory.path)
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    private enum LintError: Error {
        case sourceDirectoryMissing(String)
    }
}
