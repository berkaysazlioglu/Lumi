import AppKit
import XCTest
@testable import LumiUI

/// `LumiFonts.mono(family:size:)` çözümleme + fallback davranışı.
final class LumiFontsTests: XCTestCase {

    func testEmptyFamilyResolvesToBundledMono() {
        let font = LumiFonts.mono(family: "", size: 13)
        let bundled = LumiFonts.mono(size: 13)
        XCTAssertEqual(font.fontName, bundled.fontName,
                       "Boş aile bundle'daki JetBrains Mono'ya (veya sistem fallback'ine) çözülmeli")
        XCTAssertEqual(font.pointSize, 13)
    }

    func testWhitespaceFamilyTreatedAsEmpty() {
        let font = LumiFonts.mono(family: "   ", size: 14)
        let bundled = LumiFonts.mono(size: 14)
        XCTAssertEqual(font.fontName, bundled.fontName)
    }

    func testKnownMonospaceFamilyResolves() {
        // Menlo her macOS'ta mevcut bir sabit-genişlikli ailedir
        let font = LumiFonts.mono(family: "Menlo", size: 15)
        XCTAssertTrue(font.familyName?.contains("Menlo") ?? false,
                      "Menlo ailesine çözülmeli, çözülen: \(font.familyName ?? "nil")")
        XCTAssertEqual(font.pointSize, 15)
    }

    func testUnknownFamilyFallsBackToBundledMono() {
        let font = LumiFonts.mono(family: "ThisFontDefinitelyDoesNotExist12345", size: 12)
        let bundled = LumiFonts.mono(size: 12)
        XCTAssertEqual(font.fontName, bundled.fontName,
                       "Bilinmeyen aile JetBrains Mono fallback'ine düşmeli (sistem default'una değil)")
    }

    func testAvailableMonospaceFamiliesAreFixedPitch() {
        let families = LumiFonts.availableMonospaceFamilies
        XCTAssertFalse(families.isEmpty, "En az bir monospace aile beklenir (Menlo vb.)")
        // Örnek doğrulama: dönen her aileden bir font fixed-pitch olmalı
        for family in families.prefix(5) {
            let font = NSFont(name: family, size: 12)
            if let font {
                XCTAssertTrue(font.isFixedPitch, "'\(family)' fixed-pitch olmalı")
            }
        }
    }
}
