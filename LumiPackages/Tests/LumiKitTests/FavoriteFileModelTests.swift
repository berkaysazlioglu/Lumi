import XCTest
@testable import LumiKit

final class FavoriteFileModelTests: XCTestCase {
    // MARK: - Relative path guard

    func testRelativePathCannotEscapeTheCheckout() {
        XCTAssertTrue(FavoriteFilePath.isValidRelative("Assets/Scripts/Player.cs"))
        XCTAssertTrue(FavoriteFilePath.isValidRelative("README.md"))
        for invalid in ["", "/etc/hosts", "../secret", "a/../b", "a//b", "./a", "a/"] {
            XCTAssertFalse(FavoriteFilePath.isValidRelative(invalid), invalid)
        }
    }

    func testNameDirectoryAndAbsolute() {
        let favorite = ProjectFavoriteFile(projectPath: "/p", relativePath: "Assets/Scripts/Player.cs")
        XCTAssertEqual(favorite.name, "Player.cs")
        XCTAssertEqual(favorite.directory, "Assets/Scripts")
        XCTAssertEqual(ProjectFavoriteFile(projectPath: "/p", relativePath: "README.md").directory, "")
        XCTAssertEqual(FavoriteFilePath.absolute("a/b.txt", in: "/w"), "/w/a/b.txt")
        XCTAssertEqual(FavoriteFilePath.absolute("a/b.txt", in: "/w/"), "/w/a/b.txt")
    }

    // MARK: - Resolver

    private func locate(_ path: String, existing: Set<String>, files: [String]?, excluding: Set<String> = []) -> FavoriteFileLocation {
        FavoriteFileResolver.locate(path, fileExists: { existing.contains($0) }, files: files, excluding: excluding)
    }

    func testPresentFileIsNotSearched() {
        XCTAssertEqual(locate("a/x.cs", existing: ["a/x.cs"], files: nil), .present)
    }

    func testDeletedFileWithoutCandidateIsMissing() {
        XCTAssertEqual(locate("a/x.cs", existing: [], files: ["a/y.cs"]), .missing)
    }

    func testTreeNotLoadedYetIsMissingNotGuessed() {
        XCTAssertEqual(locate("a/x.cs", existing: ["b/x.cs"], files: nil), .missing)
    }

    func testSingleSameNameCandidateIsTheMove() {
        let files = ["Assets/Player/Player.cs", "Assets/Enemy.cs"]
        XCTAssertEqual(
            locate("Assets/Scripts/Player.cs", existing: Set(files), files: files),
            .moved(to: "Assets/Player/Player.cs")
        )
    }

    func testClosestCandidateWinsBySharedDirectories() {
        let files = ["Assets/Scripts/Player/Foo.cs", "Tests/Foo.cs"]
        XCTAssertEqual(
            locate("Assets/Scripts/Foo.cs", existing: Set(files), files: files),
            .moved(to: "Assets/Scripts/Player/Foo.cs")
        )
    }

    func testTiedCandidatesAreNotGuessed() {
        let files = ["A/Foo.cs", "B/Foo.cs"]
        XCTAssertEqual(locate("C/Foo.cs", existing: Set(files), files: files), .missing)
    }

    func testCandidateAlreadyFavoritedIsSkipped() {
        let files = ["B/Foo.cs"]
        XCTAssertEqual(locate("A/Foo.cs", existing: Set(files), files: files, excluding: ["B/Foo.cs"]), .missing)
    }

    func testCandidateGoneFromDiskSinceTreeScanIsMissing() {
        XCTAssertEqual(locate("A/Foo.cs", existing: [], files: ["B/Foo.cs"]), .missing)
    }

    func testEntryResolvedPath() {
        let favorite = ProjectFavoriteFile(projectPath: "/p", relativePath: "a.txt")
        XCTAssertEqual(FavoriteFileEntry(favorite: favorite, location: .present).resolvedPath, "a.txt")
        XCTAssertEqual(FavoriteFileEntry(favorite: favorite, location: .moved(to: "b/a.txt")).resolvedPath, "b/a.txt")
        XCTAssertNil(FavoriteFileEntry(favorite: favorite, location: .missing).resolvedPath)
    }

    // MARK: - Search

    private let tree: [FileTreeNode] = [
        FileTreeNode(name: "Assets", path: "Assets", type: .folder, isIgnored: false, children: [
            FileTreeNode(name: "Scripts", path: "Assets/Scripts", type: .folder, isIgnored: false, children: [
                FileTreeNode(name: "Player.cs", path: "Assets/Scripts/Player.cs", type: .file, isIgnored: false),
                FileTreeNode(name: "Player.cs.meta", path: "Assets/Scripts/Player.cs.meta", type: .file, isIgnored: false),
                FileTreeNode(name: "GameManager.cs", path: "Assets/Scripts/GameManager.cs", type: .file, isIgnored: false),
            ]),
            FileTreeNode(name: "Editor", path: "Assets/Editor", type: .folder, isIgnored: false, children: [
                FileTreeNode(name: "BuildTool.cs", path: "Assets/Editor/BuildTool.cs", type: .file, isIgnored: false),
            ]),
        ]),
        FileTreeNode(name: "local.player.json", path: "local.player.json", type: .file, isIgnored: true),
        FileTreeNode(name: "MyPlayer.md", path: "MyPlayer.md", type: .file, isIgnored: false),
    ]

    private func search(_ query: String) -> [String] {
        FavoriteFileSearch.search(tree, query: query).map(\.path)
    }

    func testFileNameMatchesRankPrefixFirstAndDeprioritizedLast() {
        XCTAssertEqual(search("player"), [
            "Assets/Scripts/Player.cs",
            "MyPlayer.md",
            "Assets/Scripts/Player.cs.meta",
            "local.player.json",
        ])
    }

    func testFolderNameMatchesEveryFileInside() {
        XCTAssertEqual(search("editor"), ["Assets/Editor/BuildTool.cs"])
        XCTAssertEqual(Set(search("scripts/")), [
            "Assets/Scripts/Player.cs", "Assets/Scripts/Player.cs.meta", "Assets/Scripts/GameManager.cs",
        ])
    }

    func testEveryTokenMustMatchSomewhereInThePath() {
        XCTAssertEqual(search("scripts game"), ["Assets/Scripts/GameManager.cs"])
        XCTAssertEqual(search("editor player"), [])
    }

    func testFoldersAreNotResultsAndBlankQueryIsEmpty() {
        XCTAssertFalse(search("assets").contains("Assets"))
        XCTAssertEqual(search("   "), [])
    }

    func testResultLimit() {
        XCTAssertEqual(FavoriteFileSearch.search(tree, query: "s", limit: 2).count, 2)
    }

    func testFilePathsFlattenOnlyFiles() {
        XCTAssertEqual(FavoriteFileSearch.filePaths(in: tree).count, 6)
    }
}
