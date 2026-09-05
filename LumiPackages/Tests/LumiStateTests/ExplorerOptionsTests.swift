import XCTest
import LumiKit
@testable import LumiState

final class ExplorerOptionsTests: XCTestCase {
    private func file(_ name: String, _ path: String? = nil, ignored: Bool = false) -> FileTreeNode {
        FileTreeNode(name: name, path: path ?? name, type: .file, isIgnored: ignored)
    }

    func testUnityAssetsOnlyPreservesAssetsPathsAndRemovesMetaRecursively() {
        let nested = FileTreeNode(name: "Sub", path: "Assets/Sub", type: .folder, isIgnored: false,
                                  children: [file("ok.cs", "Assets/Sub/ok.cs"), file("ok.meta", "Assets/Sub/ok.meta")])
        let assets = FileTreeNode(name: "Assets", path: "Assets", type: .folder, isIgnored: false,
                                  children: [file("root.meta", "Assets/root.meta"), nested])
        let other = file("ProjectSettings", ignored: false)
        var options = ExplorerOptions(); options.unityAssetsOnly = true
        let result = options.project([assets, other], isUnityProject: true)
        XCTAssertEqual(result.map(\.path), ["Assets/Sub"])
        XCTAssertEqual(result[0].children.map(\.path), ["Assets/Sub/ok.cs"])
    }

    func testUnityFilterDisabledForNonUnityAndTogglesRestoreNormalTree() {
        var options = ExplorerOptions(); options.unityAssetsOnly = true
        let nodes = [file(".env"), file("ignored", ignored: true)]
        XCTAssertEqual(options.project(nodes, isUnityProject: false).count, 1)
        options.showDotfiles = false; options.showIgnoredFiles = true
        XCTAssertEqual(options.project(nodes, isUnityProject: false).map(\.name), ["ignored"])
        options.showDotfiles = true; options.showIgnoredFiles = false
        XCTAssertEqual(options.project(nodes, isUnityProject: false).map(\.name), [".env"])
    }

    func testDominantFolderStatusExcludesDeletedDescendants() {
        let statuses = ExplorerGitDecoration.statuses([
            GitFileChange(path: "Assets/a.cs", status: .deleted),
            GitFileChange(path: "Assets/b.cs", status: .untracked),
            GitFileChange(path: "Assets/c.cs", status: .modified)
        ])
        XCTAssertEqual(statuses["Assets"], .modified)
        XCTAssertEqual(statuses["Assets/a.cs"], .deleted)
    }
}
