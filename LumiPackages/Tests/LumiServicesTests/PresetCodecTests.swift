import Foundation
import XCTest
import LumiKit
@testable import LumiServices

final class PresetCodecTests: XCTestCase {
    func testPersonaMissingRequiredFieldsSkippedSilently() {
        XCTAssertNil(PresetCodec.decodePersona("label: No ID", scope: .user))
        XCTAssertNil(PresetCodec.decodePersona("id: no-label", scope: .user))
        XCTAssertNil(PresetCodec.decodePersona("{{{ broken", scope: .user))
    }

    func testPersonaFullDecode() throws {
        let yaml = """
        id: architect
        label: Architect
        provider: claude
        claude:
          appendSystemPrompt: be an architect
          model: opus
          allowedTools:
            - "Read"
            - "Bash(git *)"
          maxTurns: 5
        """
        let persona = try XCTUnwrap(PresetCodec.decodePersona(yaml, scope: .project))
        XCTAssertEqual(persona.id, "architect")
        XCTAssertEqual(persona.provider, .claude)
        XCTAssertEqual(persona.claude?.model, "opus")
        XCTAssertEqual(persona.claude?.allowedTools, ["Read", "Bash(git *)"])
        XCTAssertEqual(persona.claude?.maxTurns, 5)
        XCTAssertEqual(persona.scope, .project)
    }

    func testActionStepsDecodeWithDefaults() throws {
        let yaml = """
        id: deploy
        label: Deploy
        steps:
          - type: write
            content: "make deploy\\r"
          - type: wait_for
            pattern: 'deployed'
          - type: wait_for
            pattern: 'done'
            timeout: 60000
          - type: delay
            ms: 500
          - type: bogus-step
        """
        let action = try XCTUnwrap(PresetCodec.decodeAction(yaml, scope: .user))
        XCTAssertEqual(action.icon, Action.defaultIcon)
        XCTAssertEqual(action.steps.count, 4, "bilinmeyen step tipi atlanır")
        XCTAssertEqual(action.steps[0], .write(content: "make deploy\r"))
        XCTAssertEqual(
            action.steps[1],
            .waitFor(pattern: "deployed", timeoutMs: ActionStep.defaultWaitTimeoutMs)
        )
        XCTAssertEqual(action.steps[2], .waitFor(pattern: "done", timeoutMs: 60000))
        XCTAssertEqual(action.steps[3], .delay(ms: 500))
    }

    func testActionWithoutStepsSkipped() {
        XCTAssertNil(PresetCodec.decodeAction("id: x\nlabel: X", scope: .user))
        XCTAssertNil(PresetCodec.decodeAction("id: x\nlabel: X\nsteps: []", scope: .user))
    }

    func testModifiedAtDetectionQuotedAndUnquoted() {
        let quoted = "id: a\nmodified_at: \"2026-06-01T10:00:00Z\""
        XCTAssertTrue(PresetCodec.hasModifiedAt(quoted))
        // Yams quote'suz ISO'yu Date'e çevirir — yine tespit edilmeli
        let unquoted = "id: a\nmodified_at: 2026-06-01T10:00:00Z"
        XCTAssertTrue(PresetCodec.hasModifiedAt(unquoted))
        XCTAssertFalse(PresetCodec.hasModifiedAt("id: a\nlabel: x"))
    }

    func testShippedDefaultActionDecodes() throws {
        // Gerçek default seed'lerden biri (Electron'dan kopyalanan run-tests)
        let url = try XCTUnwrap(LumiServicesResources.defaultActionsDirectory?
            .appendingPathComponent("run-tests.yaml"))
        let yaml = try String(contentsOf: url, encoding: .utf8)
        let action = try XCTUnwrap(PresetCodec.decodeAction(yaml, scope: .user, isDefault: true))
        XCTAssertEqual(action.id, "run-tests")
        XCTAssertEqual(action.claude?.model, "sonnet")
        XCTAssertFalse(action.steps.isEmpty)
        guard case .write(let content) = action.steps[0] else {
            return XCTFail("write step bekleniyordu")
        }
        XCTAssertTrue(content.hasSuffix("\r"), "write içeriği \\r ile bitmeli")
    }

    func testShippedDefaultPersonasDecode() throws {
        let dir = try XCTUnwrap(LumiServicesResources.defaultPersonasDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 4) // architect, expert, fixer, reviewer
        for file in files {
            let yaml = try String(
                contentsOf: dir.appendingPathComponent(file), encoding: .utf8
            )
            XCTAssertNotNil(
                PresetCodec.decodePersona(yaml, scope: .user),
                "default persona çözümlenemedi: \(file)"
            )
        }
    }
}
