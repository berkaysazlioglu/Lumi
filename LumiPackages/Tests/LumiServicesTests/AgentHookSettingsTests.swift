import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 45: yönetilen script metni ve ayar komutu.
final class AgentHookScriptTests: XCTestCase {
    func testClaudeScriptPrintsNeutralJSONFirstAndPostsToClaudeRoute() {
        let script = AgentHookScript.posix(provider: .claude)
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(script.contains("printf '{}\\n'"), "izin hook'u boş stdout'ta fail-closed")
        XCTAssertTrue(script.contains("/hook/claude\""))
        XCTAssertTrue(script.contains("CLAUDE_JOB_DIR"))
        XCTAssertTrue(script.contains("X-Lumi-Agent-Hook-Token: ${LUMI_AGENT_HOOK_TOKEN}"))
        XCTAssertTrue(script.contains("X-Lumi-Terminal-ID: ${LUMI_TERMINAL_ID}"))
        XCTAssertTrue(script.contains("--connect-timeout 0.5 --max-time 1.5"))
        XCTAssertTrue(script.hasSuffix("exit 0\n"))
    }

    func testCodexScriptStaysSilentOnStdout() {
        let script = AgentHookScript.posix(provider: .codex)
        XCTAssertFalse(script.contains("printf '{}"), "Codex kendi onay arayüzünü gösterir; karar basılmaz")
        XCTAssertTrue(script.contains("/hook/codex\""))
        XCTAssertFalse(script.contains("CLAUDE_JOB_DIR"))
    }

    func testScriptExitsQuietlyWithoutLumiEnvironment() {
        let script = AgentHookScript.posix(provider: .claude)
        XCTAssertTrue(script.contains("[ -z \"$LUMI_TERMINAL_ID\" ] || [ -z \"$LUMI_AGENT_HOOK_PORT\" ] || [ -z \"$LUMI_AGENT_HOOK_TOKEN\" ]"))
    }

    func testManagedCommandQuotesPathAndFallsBackWhenScriptMissing() {
        let claude = AgentHookScript.managedCommand(scriptPath: "/Users/o'neil/.lumi/hooks/lumi-claude-hook.sh", provider: .claude)
        XCTAssertTrue(claude.hasPrefix("if [ -r '/Users/o'\\''neil/.lumi/hooks/lumi-claude-hook.sh' ]; then /bin/sh '"))
        XCTAssertTrue(claude.contains("printf '{}\\n'"))
        let codex = AgentHookScript.managedCommand(scriptPath: "/x/lumi-codex-hook.sh", provider: .codex)
        XCTAssertFalse(codex.contains("printf"))
        XCTAssertEqual(AgentHookScript.scriptPath(inManagedCommand: codex), "/x/lumi-codex-hook.sh")
    }

    func testNeedleDoesNotCollideWithOrcaSweeper() {
        // Orca `agent-hooks/claude-hook.sh` alt dizgisini süpürür; bizimki onu içermez.
        let needle = AgentHookScript.managedNeedle(for: .claude)
        XCTAssertEqual(needle, "hooks/lumi-claude-hook.sh")
        XCTAssertFalse(("/Users/x/.lumi/" + needle).contains("agent-hooks/claude-hook.sh"))
    }
}

/// Karar 45: `~/.claude/settings.json` hooks bölümü düzenleyicisi.
final class ClaudeHookSettingsTests: XCTestCase {
    private let command = AgentHookScript.managedCommand(scriptPath: "/Users/dev/.lumi/hooks/lumi-claude-hook.sh", provider: .claude)

    private func groups(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        ((root["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }

    func testAddsManagedGroupToEveryEventPreservingUserHooks() {
        let user: [String: Any] = ["type": "command", "command": "echo mine"]
        let root: [String: Any] = [
            "permissions": ["allow": ["Bash"]],
            "hooks": ["Stop": [["hooks": [user]]]],
        ]

        let (next, changed) = ClaudeHookSettings.applyManaged(to: root, command: command, isStale: { _ in false })

        XCTAssertTrue(changed)
        XCTAssertEqual((next["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash"], "yabancı anahtarlar korunur")
        let stop = groups(next, "Stop")
        XCTAssertEqual(stop.count, 2)
        XCTAssertEqual((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String, "echo mine")
        XCTAssertEqual((stop[1]["hooks"] as? [[String: Any]])?.first?["command"] as? String, command)
        XCTAssertEqual((stop[1]["hooks"] as? [[String: Any]])?.first?["timeout"] as? Int, ClaudeHookSettings.timeoutSeconds)
        for event in ClaudeHookSettings.events {
            XCTAssertFalse(groups(next, event.name).isEmpty, event.name)
            let ours = groups(next, event.name).last
            XCTAssertEqual(ours?["matcher"] as? String, event.matcher, event.name)
        }
    }

    func testSecondApplyIsANoOp() {
        let (once, _) = ClaudeHookSettings.applyManaged(to: [:], command: command, isStale: { _ in false })
        let (twice, changed) = ClaudeHookSettings.applyManaged(to: once, command: command, isStale: { _ in false })
        XCTAssertFalse(changed)
        XCTAssertTrue(NSDictionary(dictionary: twice).isEqual(to: once))
    }

    func testStaleLumiCommandsAreSweptButLiveOnesFromOtherHomesStay() {
        let stale = AgentHookScript.managedCommand(scriptPath: "/old/.lumi/hooks/lumi-claude-hook.sh", provider: .claude)
        let sibling = AgentHookScript.managedCommand(scriptPath: "/Users/dev/.lumi-dev/hooks/lumi-claude-hook.sh", provider: .claude)
        let root: [String: Any] = ["hooks": ["Stop": [
            ["hooks": [["type": "command", "command": stale]]],
            ["hooks": [["type": "command", "command": sibling]]],
        ]]]

        let (next, _) = ClaudeHookSettings.applyManaged(to: root, command: command, isStale: { $0 == stale })

        let commands = groups(next, "Stop").flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, [sibling, command], "dev/prod yan yana kalır; ölü ev süpürülür")
    }

    func testRemoveManagedDropsOnlyLumiEntriesAndEmptyEvents() {
        let (installed, _) = ClaudeHookSettings.applyManaged(
            to: ["hooks": ["Stop": [["hooks": [["type": "command", "command": "echo mine"]]]]]],
            command: command, isStale: { _ in false }
        )

        let (removed, changed) = ClaudeHookSettings.removeManaged(from: installed)

        XCTAssertTrue(changed)
        XCTAssertEqual(groups(removed, "Stop").count, 1)
        XCTAssertNil((removed["hooks"] as? [String: Any])?["PreToolUse"], "yalnız bizim olan event silinir")
        XCTAssertFalse(ClaudeHookSettings.removeManaged(from: removed).changed)
    }
}

/// Karar 45: `~/.codex/hooks.json` düzenleyicisi.
final class CodexHookSettingsTests: XCTestCase {
    private let command = AgentHookScript.managedCommand(scriptPath: "/Users/dev/.lumi/hooks/lumi-codex-hook.sh", provider: .codex)

    private func groups(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        ((root["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }

    func testAppendsGroupAfterExistingAndReportsIndex() {
        let orca: [String: Any] = ["hooks": [["type": "command", "command": "/bin/sh '/Users/dev/.orca/agent-hooks/codex-hook.sh'", "timeout": 10]]]
        let root: [String: Any] = ["hooks": ["Stop": [orca]], "_managed": true]

        let applied = CodexHookSettings.applyManaged(to: root, command: command)

        XCTAssertTrue(applied.changed)
        XCTAssertNil(applied.root["_managed"], "Codex bilinmeyen üst düzey alanı reddeder")
        XCTAssertEqual(groups(applied.root, "Stop").count, 2)
        XCTAssertEqual(applied.groupIndex["Stop"], 1)
        XCTAssertEqual(applied.groupIndex["SessionStart"], 0)
        XCTAssertEqual(Set(applied.groupIndex.keys), Set(CodexHookSettings.events))
    }

    func testReapplyIsStableAndReplacesStaleLumiCommand() {
        let stale = AgentHookScript.managedCommand(scriptPath: "/old/.lumi/hooks/lumi-codex-hook.sh", provider: .codex)
        let first = CodexHookSettings.applyManaged(to: ["hooks": ["Stop": [["hooks": [["type": "command", "command": stale]]]]]], command: command)
        XCTAssertEqual(groups(first.root, "Stop").count, 1, "eski Lumi grubu yerini yenisine bırakır")
        let second = CodexHookSettings.applyManaged(to: first.root, command: command)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.groupIndex, first.groupIndex)
    }

    func testRemoveManagedKeepsForeignGroups() {
        let applied = CodexHookSettings.applyManaged(to: ["hooks": ["Stop": [["hooks": [["type": "command", "command": "echo x"]]]]]], command: command)
        let (removed, changed) = CodexHookSettings.removeManaged(from: applied.root)
        XCTAssertTrue(changed)
        XCTAssertEqual(groups(removed, "Stop").count, 1)
        XCTAssertNil((removed["hooks"] as? [String: Any])?["PreToolUse"])
    }
}

/// Karar 45: Codex güven hash'i — Orca'nın kurulu `config.toml` vektörleriyle.
final class CodexHookTrustTests: XCTestCase {
    /// `~/.codex/hooks.json`'daki gerçek Orca komutu ve `config.toml`'daki hash'leri.
    private let orcaCommand = "if [ -f '/Users/bsazliogullari/.orca/agent-hooks/codex-hook.sh' ] && [ -r '/Users/bsazliogullari/.orca/agent-hooks/codex-hook.sh' ] && [ -x '/Users/bsazliogullari/.orca/agent-hooks/codex-hook.sh' ]; then /bin/sh '/Users/bsazliogullari/.orca/agent-hooks/codex-hook.sh'; else { command -p cat 2>/dev/null || cat; } >/dev/null 2>&1 || :; fi"

    func testHashMatchesOrcaVectors() {
        XCTAssertEqual(
            CodexHookTrust.trustedHash(label: "stop", command: orcaCommand, timeoutSeconds: 10),
            "sha256:0b637a03a973681bd9496c03df4d8813ac8f52766390584707f872572d34357e"
        )
        XCTAssertEqual(
            CodexHookTrust.trustedHash(label: "pre_tool_use", command: orcaCommand, timeoutSeconds: 10),
            "sha256:4a1b96ad46d4680b85df8e7fd8e88dab5bfe1a298596bbe55b928a3ca872a8fc"
        )
        XCTAssertEqual(
            CodexHookTrust.trustedHash(label: "session_start", command: orcaCommand, timeoutSeconds: 10),
            "sha256:940d0e861fa2b90b92d85b72246394facfaa6f02a2cd3a59e0052865819d1051"
        )
    }

    func testJSONStringEscapesLikeJavaScript() {
        XCTAssertEqual(CodexHookTrust.jsonString("a\"b\\c/d\né"), "\"a\\\"b\\\\c/d\\né\"")
        XCTAssertEqual(CodexHookTrust.jsonString("\u{01}"), "\"\\u0001\"")
    }

    func testKeyShape() {
        XCTAssertEqual(CodexHookTrust.key(hooksPath: "/h/.codex/hooks.json", label: "stop", group: 1), "/h/.codex/hooks.json:stop:1:0")
    }
}

/// Karar 45: `config.toml` satır düzenleyicisi — geri kalan byte-byte korunur.
final class CodexConfigTomlEditorTests: XCTestCase {
    private let entry = CodexHookTrust.Entry(key: "/h/.codex/hooks.json:stop:1:0", hash: "sha256:aaaa")

    func testAppendsStateTableAndSectionsToExistingConfig() {
        let source = "model = \"gpt-5\"\n\n[features]\njs_repl = false\n"
        let (result, changed) = CodexConfigTomlEditor.apply(to: source, desired: [entry], ownedHashes: ["sha256:aaaa"])
        XCTAssertTrue(changed)
        XCTAssertEqual(result, source + "\n[hooks.state]\n\n[hooks.state.\"/h/.codex/hooks.json:stop:1:0\"]\ntrusted_hash = \"sha256:aaaa\"\n")
        XCTAssertFalse(CodexConfigTomlEditor.apply(to: result, desired: [entry], ownedHashes: ["sha256:aaaa"]).changed)
    }

    func testUpdatesHashInPlaceAndLeavesForeignSectionsAlone() {
        let source = """
        [hooks.state]

        [hooks.state."/h/.codex/hooks.json:stop:0:0"]
        trusted_hash = "sha256:orca"

        [hooks.state."/h/.codex/hooks.json:stop:1:0"]
        trusted_hash = "sha256:old"

        [projects."/x"]
        trust_level = "trusted"

        """
        let (result, changed) = CodexConfigTomlEditor.apply(to: source, desired: [entry], ownedHashes: ["sha256:old", "sha256:aaaa"])
        XCTAssertTrue(changed)
        XCTAssertEqual(result, source.replacingOccurrences(of: "sha256:old", with: "sha256:aaaa"))
    }

    func testRemovesOwnedSectionsWhoseKeyMovedAndKeepsOthers() {
        let source = """
        [hooks.state."/h/.codex/hooks.json:stop:0:0"]
        trusted_hash = "sha256:orca"

        [hooks.state."/h/.codex/hooks.json:stop:2:0"]
        trusted_hash = "sha256:aaaa"

        """
        let (result, changed) = CodexConfigTomlEditor.apply(to: source, desired: [entry], ownedHashes: ["sha256:aaaa"])
        XCTAssertTrue(changed)
        XCTAssertFalse(result.contains(":stop:2:0"), "kaymış eski anahtar silinir")
        XCTAssertTrue(result.contains(":stop:0:0"), "Orca'nın kaydı korunur")
        XCTAssertTrue(result.contains("[hooks.state.\"/h/.codex/hooks.json:stop:1:0\"]\ntrusted_hash = \"sha256:aaaa\""))
    }

    func testUninstallRemovesAllOwnedSections() {
        let source = "[hooks.state.\"/h/.codex/hooks.json:stop:1:0\"]\ntrusted_hash = \"sha256:aaaa\"\n"
        let (result, changed) = CodexConfigTomlEditor.apply(to: source, desired: [], ownedHashes: ["sha256:aaaa"])
        XCTAssertTrue(changed)
        XCTAssertEqual(result.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }
}

/// Karar 45: `agentHooksEnabled` additive anahtarı.
final class AgentHooksConfigCodecTests: XCTestCase {
    func testMissingKeyDefaultsToEnabled() {
        XCTAssertTrue(ConfigCodec.decodeConfig(from: [:]).agentHooksEnabled)
        XCTAssertFalse(ConfigCodec.decodeConfig(from: ["agentHooksEnabled": false]).agentHooksEnabled)
    }

    func testOverlayWritesKey() {
        var config = AppConfig.defaults
        config.agentHooksEnabled = false
        XCTAssertEqual(ConfigCodec.configOverlay(config)["agentHooksEnabled"] as? Bool, false)
    }
}
