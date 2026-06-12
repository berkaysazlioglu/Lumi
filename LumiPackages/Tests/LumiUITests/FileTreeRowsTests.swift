import LumiKit
import XCTest
@testable import LumiUI

/// FileTreeRows: ağaç → düz görünür-satır listesi (render'dan ayrık saf mantık).
/// Düz liste, LazyVStack'in gerçekten lazy çalışmasının önkoşulu — recursive
/// nested-VStack render'ı büyük repoda (özellikle aramada) UI'ı donduruyordu.
final class FileTreeRowsTests: XCTestCase {
    // Fixture:
    // src/            (folder)
    //   ├── main.swift
    //   └── util/     (folder)
    //         └── helper.swift
    // build/          (folder, ignored)
    //   └── out.bin
    // README.md
    private func makeTree() -> [FileTreeNode] {
        [
            FileTreeNode(name: "src", path: "src", type: .folder, isIgnored: false, children: [
                FileTreeNode(name: "main.swift", path: "src/main.swift", type: .file, isIgnored: false),
                FileTreeNode(name: "util", path: "src/util", type: .folder, isIgnored: false, children: [
                    FileTreeNode(
                        name: "helper.swift",
                        path: "src/util/helper.swift",
                        type: .file,
                        isIgnored: false
                    ),
                ]),
            ]),
            FileTreeNode(name: "build", path: "build", type: .folder, isIgnored: true, children: [
                FileTreeNode(name: "out.bin", path: "build/out.bin", type: .file, isIgnored: true),
            ]),
            FileTreeNode(name: "README.md", path: "README.md", type: .file, isIgnored: false),
        ]
    }

    // MARK: - visibleRows (normal mod, expand durumuna bağlı)

    func testCollapsedFoldersHideChildren() {
        let rows = FileTreeRows.visibleRows(makeTree(), expanded: [])

        XCTAssertEqual(rows.map(\.path), ["src", "build", "README.md"])
        XCTAssertEqual(rows.map(\.level), [0, 0, 0])
    }

    func testExpandedFolderShowsChildrenWithIncreasedLevel() {
        let rows = FileTreeRows.visibleRows(makeTree(), expanded: ["src"])

        XCTAssertEqual(rows.map(\.path), ["src", "src/main.swift", "src/util", "build", "README.md"])
        XCTAssertEqual(rows.first { $0.path == "src/main.swift" }?.level, 1)
        // util expand edilmedi → helper görünmez
        XCTAssertFalse(rows.contains { $0.path == "src/util/helper.swift" })
    }

    func testNestedExpansion() {
        let rows = FileTreeRows.visibleRows(makeTree(), expanded: ["src", "src/util"])

        XCTAssertTrue(rows.contains { $0.path == "src/util/helper.swift" && $0.level == 2 })
    }

    func testIgnoredFolderNeverShowsChildrenEvenIfExpanded() {
        // ignored klasör expand edilemez (spec/12 §9) — expanded set'te olsa bile
        let rows = FileTreeRows.visibleRows(makeTree(), expanded: ["build"])

        XCTAssertFalse(rows.contains { $0.path == "build/out.bin" })
        XCTAssertEqual(rows.first { $0.path == "build" }?.isExpanded, false)
    }

    func testExpandedFlagReflectsState() {
        let rows = FileTreeRows.visibleRows(makeTree(), expanded: ["src"])

        XCTAssertEqual(rows.first { $0.path == "src" }?.isExpanded, true)
        XCTAssertEqual(rows.first { $0.path == "src/util" }?.isExpanded, false)
    }

    // MARK: - searchRows (arama modu: filtre + hepsi açık)

    func testSearchMatchesFileAndKeepsAncestors() {
        let rows = FileTreeRows.searchRows(makeTree(), query: "helper")

        XCTAssertEqual(rows.map(\.path), ["src", "src/util", "src/util/helper.swift"])
        XCTAssertEqual(rows.map(\.level), [0, 1, 2])
    }

    func testSearchIsCaseInsensitive() {
        let rows = FileTreeRows.searchRows(makeTree(), query: "ReAdMe")

        XCTAssertEqual(rows.map(\.path), ["README.md"])
    }

    func testSearchMatchingFolderNameKeepsAllChildren() {
        // Klasör ADI eşleşirse tüm children korunur (spec/12 §9)
        let rows = FileTreeRows.searchRows(makeTree(), query: "src")

        XCTAssertEqual(
            rows.map(\.path),
            ["src", "src/main.swift", "src/util", "src/util/helper.swift"]
        )
    }

    func testSearchDropsNonMatchingBranches() {
        let rows = FileTreeRows.searchRows(makeTree(), query: "main")

        XCTAssertEqual(rows.map(\.path), ["src", "src/main.swift"])
    }

    func testSearchExpandsAllFolders() {
        let rows = FileTreeRows.searchRows(makeTree(), query: "swift")

        for row in rows where row.type == .folder {
            XCTAssertTrue(row.isExpanded, "\(row.path) aramada açık olmalı")
        }
    }

    func testSearchNoMatchesReturnsEmpty() {
        XCTAssertTrue(FileTreeRows.searchRows(makeTree(), query: "yok-boyle-dosya").isEmpty)
    }

    func testSearchIgnoredFolderChildrenStayHidden() {
        // ignored klasörün adı eşleşse de children listelenmez (expand edilemez kuralı)
        let rows = FileTreeRows.searchRows(makeTree(), query: "build")

        XCTAssertEqual(rows.map(\.path), ["build"])
    }
}
