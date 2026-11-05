import Foundation
import LumiKit
@testable import LumiServices
import XCTest

/// Karar 142: mod klasörü — Lumi'nin modlarının kurulumu/güncellenmesi ve
/// klasörün listelenmesi. Gerçek `~/.lumi/mods`'a dokunulmaz.
final class ClaudeModServiceTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-mods-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func bundled(version: String, body: String = "export {}", legacy: [String] = []) -> BundledClaudeMod {
        BundledClaudeMod(id: "demo", version: version, legacyVersions: legacy, files: [
            ".claude-plugin/plugin.json": #"{ "name": "demo", "version": "\#(version)", "description": "d" }"#,
            "hooks/register.ts": body,
        ])
    }

    private func service(_ mods: [BundledClaudeMod]) -> ClaudeModService {
        ClaudeModService(directory: root, bundled: mods)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func writeFolder(_ id: String, manifest: String?, files: [String: String] = [:]) throws {
        let folder = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true
        )
        if let manifest {
            try manifest.write(to: folder.appendingPathComponent(".claude-plugin/plugin.json"),
                               atomically: true, encoding: .utf8)
        }
        for (path, contents) in files {
            let file = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    func testListIsEmptyWhenFolderIsMissing() async {
        let mods = await service([]).list()

        XCTAssertEqual(mods, [])
    }

    func testInstallWritesMarkedModAndLeavesNoStagingFolder() async throws {
        let service = service([bundled(version: "1.0.0")])

        try await service.installBundled()
        let mods = await service.list()

        XCTAssertEqual(try read("demo/hooks/register.ts"), "export {}")
        XCTAssertEqual(try read("demo/\(ClaudeModService.bundledMarker)"), "1.0.0")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["demo"])
        XCTAssertEqual(mods, [ClaudeMod(
            id: "demo", name: "demo", description: "d", version: "1.0.0",
            path: root.appendingPathComponent("demo").path, isBundled: true
        )])
    }

    func testInstallKeepsSameVersionAndReplacesWholeFolderOnNewVersion() async throws {
        try await service([bundled(version: "1.0.0")]).installBundled()
        try "edited".write(to: root.appendingPathComponent("demo/hooks/register.ts"), atomically: true, encoding: .utf8)
        try "stale".write(to: root.appendingPathComponent("demo/hooks/old.ts"), atomically: true, encoding: .utf8)

        try await service([bundled(version: "1.0.0")]).installBundled()
        XCTAssertEqual(try read("demo/hooks/register.ts"), "edited")

        try await service([bundled(version: "1.1.0", body: "v2")]).installBundled()
        XCTAssertEqual(try read("demo/hooks/register.ts"), "v2")
        // Klasör bütün olarak değişir: eski sürümden dosya kalmaz.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("demo/hooks/old.ts").path))
    }

    func testUserFolderWithSameNameIsNeverTouchedOrTreatedAsLumis() async throws {
        try writeFolder("demo", manifest: #"{ "name": "my demo", "version": "9.9.9" }"#,
                        files: ["hooks/register.ts": "mine"])
        let service = service([bundled(version: "1.0.0")])

        try await service.installBundled()
        let mods = await service.list()

        XCTAssertEqual(try read("demo/hooks/register.ts"), "mine")
        XCTAssertEqual(mods.map(\.isBundled), [false])
    }

    func testUnmarkedLegacyInstallIsAdoptedAndUpdated() async throws {
        // İşaretten önceki Lumi kurulumu: kendi adı + bilinen eski sürüm.
        try writeFolder("demo", manifest: #"{ "name": "demo", "version": "1.0.0" }"#,
                        files: ["hooks/register.ts": "old"])
        let service = service([bundled(version: "1.0.1", body: "new", legacy: ["1.0.0"])])

        try await service.installBundled()
        let mods = await service.list()

        XCTAssertEqual(try read("demo/hooks/register.ts"), "new")
        XCTAssertEqual(mods.map(\.isBundled), [true])
    }

    func testMarkerOutsideLumisModNamesDoesNotMakeAModBundled() async throws {
        try writeFolder("intruder", manifest: #"{ "name": "intruder" }"#,
                        files: [ClaudeModService.bundledMarker: "1.0.0"])

        let mods = await service([bundled(version: "1.0.0")]).list()

        XCTAssertEqual(mods.map(\.isBundled), [false])
    }

    func testListsUserModsSortedAndSkipsInvalidFolders() async throws {
        try writeFolder("zeta", manifest: #"{ "name": "zeta" }"#)
        try writeFolder("alpha-folder", manifest: #"{ "name": "Alpha", "version": "2.0.0" }"#)
        try writeFolder("no-manifest", manifest: nil)
        try writeFolder("broken", manifest: "not json")
        // `CLAUDE_CODE_PLUGIN_DIRS` `:` ile ayrılır — böyle yol listeyi bozardı.
        try writeFolder("a:b", manifest: #"{ "name": "colon" }"#)

        let mods = await service([]).list()

        XCTAssertEqual(mods.map(\.id), ["alpha-folder", "zeta"])
        XCTAssertEqual(mods.first?.name, "Alpha")
        XCTAssertEqual(mods.first?.isBundled, false)
    }

    func testRealBundledModsCarryManifestMatchingTheirVersion() throws {
        for mod in BundledClaudeMods.all {
            let data = try XCTUnwrap(mod.files[".claude-plugin/plugin.json"]?.data(using: .utf8))
            let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(manifest["name"] as? String, mod.id)
            // Sürüm farkı kurulumda üzerine yazmanın tek tetiğidir.
            XCTAssertEqual(manifest["version"] as? String, mod.version)
            XCTAssertFalse(mod.legacyVersions.contains(mod.version))
            // Her mod en az bir yetenek taşır: hook (image-preview) ya da MCP sunucusu (lumi-remote, karar 143).
            XCTAssertTrue(mod.files["hooks/hooks.json"] != nil || mod.files[".mcp.json"] != nil, mod.id)
        }
    }
}
