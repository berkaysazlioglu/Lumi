import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// Faz 5 çıkış kriterleri: seed asimetrisi (persona ezilir / modified_at'li
/// action korunur), .history max-20 + restore, id-alanına-göre silme.
@MainActor
final class PresetSeedingTests: XCTestCase {
    private var tempHome: URL!
    private var seedActions: URL!
    private var seedPersonas: URL!
    private var paths: LumiPaths!
    private var terminal: StubTerminalService!
    private var config: StubConfigService!

    override func setUp() async throws {
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-preset-\(UUID().uuidString)")
        seedActions = tempHome.appendingPathComponent("seed-actions")
        seedPersonas = tempHome.appendingPathComponent("seed-personas")
        for dir in [seedActions, seedPersonas] {
            try FileManager.default.createDirectory(at: dir!, withIntermediateDirectories: true)
        }
        paths = LumiPaths(mode: .development, homeDirectory: tempHome)
        try paths.ensureDirectoriesExist()
        terminal = StubTerminalService()
        config = StubConfigService()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    private func writeSeedAction(_ name: String, id: String, label: String = "Seed Label") throws {
        let yaml = """
        id: \(id)
        label: \(label)
        steps:
          - type: write
            content: "echo seed\\r"
        """
        try yaml.write(
            to: seedActions.appendingPathComponent("\(name).yaml"),
            atomically: true, encoding: .utf8
        )
    }

    private func makeActionService() -> ActionService {
        ActionService(
            paths: paths, seedDirectory: seedActions, terminal: terminal, config: config
        )
    }

    private func userActionFile(_ name: String) -> URL {
        paths.actionsDir.appendingPathComponent("\(name).yaml")
    }

    // MARK: - Seed asimetrisi (faz çıkış kriteri)

    func testActionSeedPreservesUserEditWithModifiedAt() async throws {
        try writeSeedAction("alpha", id: "alpha")
        let service = makeActionService()
        await service.seedDefaults()

        // Kullanıcı düzenlemesi: modified_at eklendi
        let edited = """
        id: alpha
        label: User Edited
        modified_at: "2026-06-01T10:00:00Z"
        steps:
          - type: write
            content: "echo edited\\r"
        """
        try edited.write(to: userActionFile("alpha"), atomically: true, encoding: .utf8)

        await service.seedDefaults() // restart simülasyonu
        let actions = await service.actions(projectPath: nil)
        let alpha = try XCTUnwrap(actions.first { $0.id == "alpha" })
        XCTAssertEqual(alpha.label, "User Edited", "modified_at'li düzenleme KORUNMALI")
        XCTAssertTrue(alpha.isDefault, "id yine default işaretli kalır")
    }

    func testActionSeedOverwritesWithoutModifiedAtAndParseBroken() async throws {
        try writeSeedAction("alpha", id: "alpha", label: "Canonical")
        let service = makeActionService()
        await service.seedDefaults()

        // modified_at'siz düzenleme → seed'de ezilir
        let editedNoStamp = """
        id: alpha
        label: Sneaky Edit
        steps:
          - type: write
            content: "echo x\\r"
        """
        try editedNoStamp.write(to: userActionFile("alpha"), atomically: true, encoding: .utf8)
        await service.seedDefaults()
        var actions = await service.actions(projectPath: nil)
        XCTAssertEqual(actions.first { $0.id == "alpha" }?.label, "Canonical")

        // parse-bozuk dosya → ezilir
        try "{{{ broken".write(to: userActionFile("alpha"), atomically: true, encoding: .utf8)
        await service.seedDefaults()
        actions = await service.actions(projectPath: nil)
        XCTAssertEqual(actions.first { $0.id == "alpha" }?.label, "Canonical")
    }

    func testDeprecatedDefaultFilesRemoved() async throws {
        try FileManager.default.createDirectory(
            at: paths.actionsDir, withIntermediateDirectories: true
        )
        let deprecated = userActionFile("git-pull")
        try "id: git-pull\nlabel: Old\nsteps:\n  - type: delay\n    ms: 1".write(
            to: deprecated, atomically: true, encoding: .utf8
        )
        let service = makeActionService()
        await service.seedDefaults()
        XCTAssertFalse(FileManager.default.fileExists(atPath: deprecated.path))
    }

    func testPersonaSeedAlwaysOverwrites() async throws {
        let personaSeed = """
        id: architect
        label: Architect
        claude:
          appendSystemPrompt: canonical prompt
        """
        try personaSeed.write(
            to: seedPersonas.appendingPathComponent("architect.yaml"),
            atomically: true, encoding: .utf8
        )
        let service = PersonaService(
            paths: paths, seedDirectory: seedPersonas, terminal: terminal, config: config
        )
        await service.seedDefaults()

        // Kullanıcı düzenler (modified_at bile olsa fark etmez — persona tarafı)
        let edited = """
        id: architect
        label: My Custom Architect
        modified_at: "2026-06-01T10:00:00Z"
        """
        try edited.write(
            to: paths.personasDir.appendingPathComponent("architect.yaml"),
            atomically: true, encoding: .utf8
        )

        await service.seedDefaults() // restart → EZİLİR (spec/13 §2.2, bilinçli)
        let personas = await service.personas(projectPath: nil)
        XCTAssertEqual(personas.first { $0.id == "architect" }?.label, "Architect")
    }

    // MARK: - .history (faz çıkış kriteri: max 20 + restore)

    func testHistoryBackupCapAtTwenty() async throws {
        try writeSeedAction("alpha", id: "alpha")
        let service = makeActionService()
        await service.seedDefaults()

        for index in 0..<25 {
            let edited = """
            id: alpha
            label: Edit \(index)
            modified_at: "2026-06-01T10:00:0\(index % 10)Z"
            steps:
              - type: write
                content: "echo \(index)\\r"
            """
            try edited.write(to: userActionFile("alpha"), atomically: true, encoding: .utf8)
            await service.handleUserDirectoryChange()
        }

        let versions = await service.history(actionID: "alpha")
        XCTAssertEqual(versions.count, ActionService.maxHistoryPerAction, "max 20 backup")
        // Yeniden eskiye sıralı
        XCTAssertEqual(versions.map(\.timestamp), versions.map(\.timestamp).sorted(by: >))
    }

    func testRestoreCopiesBackupOverActiveFile() async throws {
        try writeSeedAction("alpha", id: "alpha", label: "Original")
        let service = makeActionService()
        await service.seedDefaults()

        let edited = """
        id: alpha
        label: Changed
        modified_at: "2026-06-01T10:00:00Z"
        steps:
          - type: write
            content: "echo changed\\r"
        """
        try edited.write(to: userActionFile("alpha"), atomically: true, encoding: .utf8)
        await service.handleUserDirectoryChange() // backup: "Changed" hali

        let other = edited.replacingOccurrences(of: "Changed", with: "Latest")
        try other.write(to: userActionFile("alpha"), atomically: true, encoding: .utf8)
        await service.handleUserDirectoryChange()

        let versions = await service.history(actionID: "alpha")
        XCTAssertGreaterThanOrEqual(versions.count, 2)
        // En eski backup "Changed" sürümüdür → ona dön
        let oldest = try XCTUnwrap(versions.last)
        try await service.restore(actionID: "alpha", version: oldest.timestamp)

        let actions = await service.actions(projectPath: nil)
        XCTAssertEqual(actions.first { $0.id == "alpha" }?.label, "Changed")
    }

    func testDeletedDefaultIsReseededOnDirectoryChange() async throws {
        try writeSeedAction("alpha", id: "alpha", label: "Canonical")
        let service = makeActionService()
        await service.seedDefaults()

        try FileManager.default.removeItem(at: userActionFile("alpha"))
        await service.handleUserDirectoryChange()

        // Silinen default anında geri gelir (spec/13 §3.3 — defaultlar silinemez)
        XCTAssertTrue(FileManager.default.fileExists(atPath: userActionFile("alpha").path))
        let actions = await service.actions(projectPath: nil)
        XCTAssertEqual(actions.first { $0.id == "alpha" }?.label, "Canonical")
    }

    // MARK: - id-alanına göre silme (spec/13 §3.5)

    func testDeleteFindsFileByIDFieldNotFilename() async throws {
        let service = makeActionService()
        await service.seedDefaults()

        // Dosya adı id ile FARKLI
        let custom = """
        id: my-custom-action
        label: Custom
        steps:
          - type: write
            content: "echo hi\\r"
        """
        let weirdFile = paths.actionsDir.appendingPathComponent("totally-different-name.yaml")
        try custom.write(to: weirdFile, atomically: true, encoding: .utf8)

        try await service.delete(actionID: "my-custom-action", scope: .user, projectPath: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: weirdFile.path))
    }

    func testProjectActionsHideUserActionsByID() async throws {
        try writeSeedAction("alpha", id: "alpha", label: "User Version")
        let service = makeActionService()
        await service.seedDefaults()

        let projectDir = tempHome.appendingPathComponent("repo/.lumi/actions")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let projectAction = """
        id: alpha
        label: Project Version
        steps:
          - type: write
            content: "echo p\\r"
        """
        try projectAction.write(
            to: projectDir.appendingPathComponent("alpha.yaml"),
            atomically: true, encoding: .utf8
        )

        let merged = await service.actions(projectPath: tempHome.appendingPathComponent("repo").path)
        let alphas = merged.filter { $0.id == "alpha" }
        XCTAssertEqual(alphas.count, 1)
        XCTAssertEqual(alphas.first?.label, "Project Version", "project, user'ı id ile gizler")
        XCTAssertEqual(alphas.first?.scope, .project)
    }
}
