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

    private func bundled(version: String, body: String = "export {}") -> BundledClaudeMod {
        BundledClaudeMod(id: "demo", version: version, files: [
            ".claude-plugin/plugin.json": #"{ "name": "Demo", "version": "\#(version)", "description": "d" }"#,
            "hooks/register.ts": body,
        ])
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func writeUserMod(_ id: String, manifest: String?) throws {
        let folder = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true
        )
        if let manifest {
            try manifest.write(to: folder.appendingPathComponent(".claude-plugin/plugin.json"),
                               atomically: true, encoding: .utf8)
        }
    }

    func testListIsEmptyWhenFolderIsMissing() async {
        let service = ClaudeModService(directory: root, bundled: [])

        let mods = await service.list()

        XCTAssertEqual(mods, [])
    }

    func testInstallWritesBundledModAndListMarksItBundled() async throws {
        let service = ClaudeModService(directory: root, bundled: [bundled(version: "1.0.0")])

        try await service.installBundled()
        let mods = await service.list()

        XCTAssertEqual(try read("demo/hooks/register.ts"), "export {}")
        XCTAssertEqual(mods, [ClaudeMod(
            id: "demo", name: "Demo", description: "d", version: "1.0.0",
            path: root.appendingPathComponent("demo").path, isBundled: true
        )])
    }

    func testInstallKeepsSameVersionAndOverwritesOnNewVersion() async throws {
        try await ClaudeModService(directory: root, bundled: [bundled(version: "1.0.0")]).installBundled()
        try "edited".write(to: root.appendingPathComponent("demo/hooks/register.ts"), atomically: true, encoding: .utf8)

        try await ClaudeModService(directory: root, bundled: [bundled(version: "1.0.0")]).installBundled()
        XCTAssertEqual(try read("demo/hooks/register.ts"), "edited")

        try await ClaudeModService(directory: root, bundled: [bundled(version: "1.1.0", body: "v2")]).installBundled()
        XCTAssertEqual(try read("demo/hooks/register.ts"), "v2")
    }

    func testListsUserModsSortedAndSkipsFoldersWithoutManifest() async throws {
        try writeUserMod("zeta", manifest: #"{ "name": "zeta" }"#)
        try writeUserMod("alpha-folder", manifest: #"{ "name": "Alpha", "version": "2.0.0" }"#)
        try writeUserMod("no-manifest", manifest: nil)
        try writeUserMod("broken", manifest: "not json")
        let service = ClaudeModService(directory: root, bundled: [])

        let mods = await service.list()

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
            XCTAssertNotNil(mod.files["hooks/hooks.json"])
        }
    }
}
