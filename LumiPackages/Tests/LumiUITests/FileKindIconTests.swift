import LumiKit
import XCTest
@testable import LumiUI

/// Dosya türü ikonunun sunum eşlemeleri: her sınıfın bir glyph'i ve bir rengi
/// olmalı; Unity'nin dört asset türü bundle PNG'sine bağlanmalı.
@MainActor
final class FileKindIconTests: XCTestCase {
    func testEveryKindHasANonEmptySymbolName() {
        for kind in FileKind.allCases {
            XCTAssertFalse(FileKindIcon.symbolName(for: kind).isEmpty, "\(kind) glyph'siz")
        }
    }

    func testOnlyUnityAssetKindsUseBundledIcons() {
        let bundled = FileKind.allCases.filter { FileKindIcon.unityIconName(for: $0) != nil }
        XCTAssertEqual(
            Set(bundled),
            [.unityScene, .unityPrefab, .unityScriptableObject, .unityMaterial]
        )
    }

    func testUnityIconNamesAreDistinct() {
        let names = FileKind.allCases.compactMap(FileKindIcon.unityIconName(for:))
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testBundledUnityIconsLoadFromResources() {
        for name in LumiAssets.UnityIconName.allCases {
            XCTAssertNotNil(LumiAssets.unityIcon(name), "unity-\(name.rawValue).png bundle'da yok")
        }
    }

    func testFolderKindsShareTheFolderColor() {
        XCTAssertEqual(Theme.fileColor(for: .folder), Theme.FileColor.folder)
        XCTAssertEqual(Theme.fileColor(for: .folderOpen), Theme.FileColor.folder)
    }

    func testSearchModesHaveDistinctTitlesAndPlaceholders() {
        let titles = ExplorerSearchMode.allCases.map(\.title)
        let placeholders = ExplorerSearchMode.allCases.map(\.placeholder)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertEqual(Set(placeholders).count, placeholders.count)
        XCTAssertFalse(placeholders.contains(where: \.isEmpty))
    }

    func testContentSearchSummaryUsesSingularAndPluralLabels() {
        XCTAssertEqual(
            ExplorerContentSearchView.summaryText(matches: 1, files: 1),
            "1 result in 1 file"
        )
        XCTAssertEqual(
            ExplorerContentSearchView.summaryText(matches: 12, files: 3),
            "12 results in 3 files"
        )
    }

    func testCSharpAndMarkdownUseJetBrainsStyleTextGlyphs() {
        XCTAssertEqual(FileKindIcon.textGlyph(for: .csharp), "C#")
        XCTAssertEqual(FileKindIcon.textGlyph(for: .markdown), "M↓")
        XCTAssertNil(FileKindIcon.textGlyph(for: .swift))
    }
}
