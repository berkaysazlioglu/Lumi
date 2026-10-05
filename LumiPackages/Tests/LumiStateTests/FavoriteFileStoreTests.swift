import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class FavoriteFileStoreTests: XCTestCase {
    private var config: FakeConfigService!
    private var toasts: ToastStore!
    private var store: FavoriteFileStore!
    private var root: URL!

    override func setUp() async throws {
        config = FakeConfigService()
        toasts = ToastStore()
        store = FavoriteFileStore(config: config, toasts: toasts)
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lumi-fav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var project: String { root.path }

    private func touch(_ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    private func move(_ from: String, _ to: String) throws {
        let target = root.appendingPathComponent(to)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent(from), to: target)
    }

    private func tree(_ files: [String]) -> [FileTreeNode] {
        files.map { FileTreeNode(name: FavoriteFilePath.name(of: $0), path: $0, type: .file, isIgnored: false) }
    }

    // MARK: - Düzenleme

    func testAddIsIdempotentAndToggleRemoves() async {
        let added = await store.add("Assets/A.cs", to: "/p")
        let again = await store.add("Assets/A.cs", to: "/p")
        XCTAssertTrue(added)
        XCTAssertFalse(again, "aynı dosya iki kez eklenmez")
        await store.add("B.cs", to: "/q")
        XCTAssertEqual(store.favorites(for: "/p").map(\.relativePath), ["Assets/A.cs"])

        await store.toggle("Assets/A.cs", in: "/p")
        XCTAssertFalse(store.isFavorite("Assets/A.cs", in: "/p"))
        let persisted = await config.config().projectFavoriteFiles
        XCTAssertEqual(persisted.map(\.relativePath), ["B.cs"])
    }

    func testEscapingPathIsNotWritten() async {
        let added = await store.add("../outside.txt", to: "/p")
        XCTAssertFalse(added)
        let writes = await config.configUpdateCount
        XCTAssertEqual(writes, 0)
    }

    func testLoadReadsPersistedFavorites() async {
        var seeded = AppConfig.defaults
        seeded.projectFavoriteFiles = [ProjectFavoriteFile(id: "1", projectPath: "/p", relativePath: "a.txt")]
        await config.seed(seeded)
        await store.load()
        XCTAssertEqual(store.favorites.map(\.id), ["1"])
    }

    func testWriteFailureShowsToast() async {
        await config.setUpdateConfigError(.configIOFailed(file: "/x", detail: "disk full"))
        let added = await store.add("a.txt", to: "/p")
        XCTAssertFalse(added)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertEqual(toasts.toasts.first?.kind, .error)
    }

    func testRelinkMovesPathAndDropsDuplicate() async throws {
        await store.add("old/A.cs", to: "/p")
        await store.add("new/B.cs", to: "/p")
        let first = try XCTUnwrap(store.favorites.first)

        await store.relink(id: first.id, to: "moved/A.cs")
        XCTAssertEqual(store.favorites(for: "/p").map(\.relativePath), ["moved/A.cs", "new/B.cs"])

        await store.relink(id: first.id, to: "new/B.cs")
        XCTAssertEqual(store.favorites(for: "/p").map(\.relativePath), ["new/B.cs"], "aynı dosya iki kez listelenmez")
    }

    // MARK: - Silinen / taşınan dosyalar (gerçek dosya sistemi)

    func testDeletedFileIsMissingAndNotOpenable() async throws {
        try touch("Docs/Notes.md")
        await store.add("Docs/Notes.md", to: project)
        XCTAssertEqual(store.entries(projectPath: project, checkoutPath: project, tree: tree(["Docs/Notes.md"])).first?.location, .present)

        try FileManager.default.removeItem(at: root.appendingPathComponent("Docs/Notes.md"))
        let entry = try XCTUnwrap(store.entries(projectPath: project, checkoutPath: project, tree: tree(["Docs/Notes.md"])).first)
        XCTAssertEqual(entry.location, .missing, "bayat ağaçtaki eski yol aday sayılmaz")
        XCTAssertNil(entry.resolvedPath)
        XCTAssertFalse(store.fileExists("Docs/Notes.md", in: project))
    }

    func testReplacedByFolderIsMissing() async throws {
        try touch("Docs/Notes.md/inner.txt")
        await store.add("Docs/Notes.md", to: project)
        XCTAssertEqual(store.entries(projectPath: project, checkoutPath: project, tree: []).first?.location, .missing)
    }

    func testMovedFileIsFoundAndPersistedInProjectRoot() async throws {
        try touch("Assets/Scripts/Player.cs")
        await store.add("Assets/Scripts/Player.cs", to: project)
        try move("Assets/Scripts/Player.cs", "Assets/Scripts/Characters/Player.cs")

        let entries = store.entries(
            projectPath: project, checkoutPath: project, tree: tree(["Assets/Scripts/Characters/Player.cs"])
        )
        XCTAssertEqual(entries.first?.location, .moved(to: "Assets/Scripts/Characters/Player.cs"))
        XCTAssertEqual(entries.first?.resolvedPath, "Assets/Scripts/Characters/Player.cs")

        await store.persistMoves(entries)
        XCTAssertEqual(store.favorites.first?.relativePath, "Assets/Scripts/Characters/Player.cs")
        let afterHeal = store.entries(projectPath: project, checkoutPath: project, tree: nil)
        XCTAssertEqual(afterHeal.first?.location, .present)
    }

    func testPersistMovesWithoutMovesDoesNotWrite() async throws {
        try touch("a.txt")
        await store.add("a.txt", to: project)
        let before = await config.configUpdateCount
        await store.persistMoves(store.entries(projectPath: project, checkoutPath: project, tree: nil))
        let after = await config.configUpdateCount
        XCTAssertEqual(before, after)
    }

    func testFavoritesResolveAgainstTheGivenCheckout() async throws {
        let workspace = root.appendingPathComponent("ws").path
        try touch("ws/src/main.swift")
        await store.add("src/main.swift", to: project)
        XCTAssertEqual(store.entries(projectPath: project, checkoutPath: project, tree: []).first?.location, .missing)
        XCTAssertEqual(store.entries(projectPath: project, checkoutPath: workspace, tree: []).first?.location, .present)
    }
}
