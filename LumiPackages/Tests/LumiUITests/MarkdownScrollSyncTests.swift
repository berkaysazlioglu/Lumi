import AppKit
import LumiKit
import LumiTestSupport
import SwiftUI
import XCTest
@testable import LumiUI

/// Karar 113: Both'ta editör ↔ önizleme kaydırma senkronu.
@MainActor
final class MarkdownScrollSyncTests: XCTestCase {
    // MARK: - Saf eşleme

    func testMapInterpolatesBetweenBlockAnchorsBothWays() {
        let map = ScrollSyncMap(
            anchors: [.init(line: 11, offset: 100), .init(line: 21, offset: 400)],
            endLine: 31, endOffset: 500
        )
        XCTAssertEqual(map.offset(forLine: 1), 0)
        XCTAssertEqual(map.offset(forLine: 6), 50, accuracy: 0.001)
        XCTAssertEqual(map.offset(forLine: 16), 250, accuracy: 0.001)
        XCTAssertEqual(map.line(forOffset: 250), 16, accuracy: 0.001)
        XCTAssertEqual(map.offset(forLine: 99), 500)
    }

    func testMapDropsNonMonotonicAnchors() {
        let map = ScrollSyncMap(
            anchors: [.init(line: 5, offset: 300), .init(line: 9, offset: 200)],
            endLine: 20, endOffset: 600
        )
        XCTAssertEqual(map.anchors.map(\.line), [1, 5, 20], "geri giden çapa atlanır")
    }

    func testLineIndexBinarySearch() {
        let starts = [0, 4, 9, 15]
        XCTAssertEqual(MarkdownScrollSync.lineIndex(of: 0, in: starts), 0)
        XCTAssertEqual(MarkdownScrollSync.lineIndex(of: 8, in: starts), 1)
        XCTAssertEqual(MarkdownScrollSync.lineIndex(of: 9, in: starts), 2)
        XCTAssertEqual(MarkdownScrollSync.lineIndex(of: 99, in: starts), 3)
    }

    // MARK: - Gerçek pencere

    func testScrollingOnePaneMovesTheOther() async throws {
        var source = ""
        var blocks: [MarkdownBlock] = []
        var lines: [Int] = []
        for section in 0..<40 {
            lines.append(source.split(separator: "\n", omittingEmptySubsequences: false).count)
            source += "## Section \(section)\n\nBody line one\nbody line two\nbody line three\n\n"
            blocks.append(.heading(level: 2, content: [.text("Section \(section)")]))
            blocks.append(.paragraph([.text("Body line one body line two body line three")]))
            lines.append(lines.last! + 2)
        }
        let document = MarkdownDocument(blocks: blocks, blockStartLines: lines)
        let sync = MarkdownScrollSync()
        let highlighter = FakeSyntaxHighlighter()
        let text = NSAttributedString(string: source, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
        let root = HStack(spacing: 0) {
            AttributedTextView(text: text, scrollSync: sync).frame(width: 400)
            MarkdownDocumentView(document: document, highlighter: highlighter, onOpenLink: { _ in }, scrollSync: sync)
                .frame(width: 400)
        }
        .frame(width: 800, height: 400)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: root)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(400))

        let scrollViews = Self.scrollViews(in: host).filter { $0.hasVerticalScroller || $0.documentView != nil }
        let editor = try XCTUnwrap(scrollViews.first { $0.documentView is NSTextView })
        let preview = try XCTUnwrap(scrollViews.first { !($0.documentView is NSTextView) && ($0.documentView?.frame.height ?? 0) > 1000 })
        XCTAssertFalse(sync.blockOffsets.isEmpty, "önizleme blok konumlarını bildirmeli")

        // Editörü 120. satıra kaydır → önizleme aynı bölüme gelmeli.
        let textView = try XCTUnwrap(editor.documentView as? NSTextView)
        let lineHeight = try XCTUnwrap(textView.layoutManager).defaultLineHeight(for: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        editor.contentView.scroll(to: NSPoint(x: 0, y: lineHeight * 120))
        editor.reflectScrolledClipView(editor.contentView)
        try await Task.sleep(for: .milliseconds(100))
        let previewTop = preview.contentView.bounds.minY
        // Editörün tepesindeki satırın bölümü önizlemenin tepesinde olmalı
        // (bölüm başına 6 satır, bölüm başına iki blok).
        let topLine = try XCTUnwrap(sync.editorTopLine())
        let section = Int((topLine - 1) / 6)
        let sectionTop = try XCTUnwrap(sync.blockOffsets[section * 2])
        let nextSectionTop = try XCTUnwrap(sync.blockOffsets[section * 2 + 2])
        XCTAssertGreaterThan(section, 5, "gerçekten aşağı kaydırıldı")
        XCTAssertGreaterThanOrEqual(previewTop, sectionTop - 1)
        XCTAssertLessThanOrEqual(previewTop, nextSectionTop + 1)

        // Önizlemeyi başa al → editör de başa döner.
        preview.contentView.scroll(to: .zero)
        preview.reflectScrolledClipView(preview.contentView)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertLessThan(editor.contentView.bounds.minY, lineHeight)
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap { scrollViews(in: $0) }
    }
}
