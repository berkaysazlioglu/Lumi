import AppKit
import LumiKit
import SwiftUI
import XCTest
@testable import LumiUI

/// Diff renk eşlemesinin TEK kaynağı (refactor 7.9): eskiden aynı eşleme
/// `SideBySideDiffView`, `MarkdownDiffView` ve `Theme.NS` içinde üç kez —
/// 0.13 opaklık dahil — kopyalanmıştı. Artık üç kullanım da `Theme+Diff`'ten türer.
@MainActor
final class ThemeDiffTests: XCTestCase {
    private func components(_ color: Color) -> [CGFloat] {
        components(NSColor(color))
    }

    private func components(_ color: NSColor) -> [CGFloat] {
        let srgb = color.usingColorSpace(.sRGB)!
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
    }

    private func assertSameColor(
        _ lhs: [CGFloat],
        _ rhs: [CGFloat],
        _ message: String,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, message, line: line)
        for (left, right) in zip(lhs, rhs) {
            XCTAssertEqual(left, right, accuracy: 0.001, message, line: line)
        }
    }

    // MARK: - Ön plan (metin) rengi

    func testForegroundMapsKindToPalette() {
        XCTAssertEqual(Theme.diffForeground(for: .addition), Theme.success)
        XCTAssertEqual(Theme.diffForeground(for: .deletion), Theme.error)
        XCTAssertEqual(Theme.diffForeground(for: .context), Theme.textPrimary)
    }

    // MARK: - Arka plan

    func testContextHasNoBackground() {
        XCTAssertEqual(Theme.diffBackground(for: .context), Color.clear)
        assertSameColor(
            components(Theme.NS.diffBackground(for: .context)),
            [0, 0, 0, 0],
            "AppKit tarafında da context zemini saydam"
        )
    }

    func testBackgroundUsesSharedOpacity() {
        assertSameColor(
            components(Theme.diffBackground(for: .addition)),
            components(Theme.success.opacity(Theme.Diff.backgroundOpacity)),
            "ekleme zemini paylaşılan opaklıktan türer"
        )
        assertSameColor(
            components(Theme.diffBackground(for: .deletion)),
            components(Theme.error.opacity(Theme.Diff.backgroundOpacity)),
            "silme zemini paylaşılan opaklıktan türer"
        )
    }

    /// Üç kullanımın (SwiftUI diff view'ları + AppKit `Theme.NS`) aynı değeri
    /// vermesi — kopyaların geri sızmasına karşı kilit.
    func testSwiftUIAndAppKitBackgroundsAgree() {
        for kind: DiffLine.Kind in [.addition, .deletion, .context] {
            assertSameColor(
                components(Theme.diffBackground(for: kind)),
                components(Theme.NS.diffBackground(for: kind)),
                "SwiftUI ve AppKit diff zemini ayrışmamalı (\(kind))"
            )
        }
    }

    func testOpacityIsTheDocumentedThirteenPercent() {
        XCTAssertEqual(Theme.Diff.backgroundOpacity, 0.13, accuracy: 0.0001)
    }
}
