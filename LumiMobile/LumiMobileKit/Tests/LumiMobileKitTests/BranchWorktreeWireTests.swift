import Testing
import Foundation
@testable import LumiMobileKit
import LumiWire

@Suite @MainActor struct BranchWorktreeWireTests {
    @Test func startSessionEncodesWorkspaceFields() throws {
        let cmd = OutgoingCommand(commandId: "c1", action: .startSession(
            repoPath: "/tmp/r", personaId: nil, prompt: "hi", kind: "chat",
            branchMode: "new", branchName: "feat", baseBranch: "main", workspaceName: "ws1"))
        let text = PhoneProtocol.commandFrame(cmd)
        let obj = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        let payload = obj["payload"] as! [String: Any]
        #expect(payload["action"] as? String == "start_session")
        #expect(payload["branchMode"] as? String == "new")
        #expect(payload["branchName"] as? String == "feat")
        #expect(payload["baseBranch"] as? String == "main")
        #expect(payload["workspaceName"] as? String == "ws1")
    }

    /// Decision 133: the `+` menu's model rides along; absent → no `model` key.
    @Test func startSessionEncodesModelOnlyWhenChosen() throws {
        func payload(_ model: ClaudeModelAlias?) throws -> [String: Any] {
            let cmd = OutgoingCommand(commandId: "c3", action: .startSession(
                repoPath: "/tmp/r", personaId: nil, prompt: "", kind: "chat", model: model))
            let text = PhoneProtocol.commandFrame(cmd)
            let obj = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
            return obj["payload"] as! [String: Any]
        }
        #expect(try payload(.sonnet)["model"] as? String == "sonnet")
        #expect(try payload(nil)["model"] == nil)
    }

    @Test func listBranchesEncodes() throws {
        let cmd = OutgoingCommand(commandId: "c2", action: .listBranches(repoPath: "/tmp/r"))
        let text = PhoneProtocol.commandFrame(cmd)
        let obj = try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
        let payload = obj["payload"] as! [String: Any]
        #expect(payload["action"] as? String == "list_branches")
        #expect(payload["repoPath"] as? String == "/tmp/r")
    }

    @Test func commandResultDecodesBranches() throws {
        let json = #"{"v":1,"type":"command_result","payload":{"commandId":"c2","ok":true,"branches":["main","dev"]}}"#
        let msg = PhoneProtocol.decodeServerMessage(json)
        guard case .commandResult(let r) = msg else { Issue.record("expected commandResult"); return }
        #expect(r.branches == ["main", "dev"])
    }

    // MARK: AppModel branch state

    private func makeModelWithFakeClient() -> (AppModel, FakeRelayClient) {
        let client = FakeRelayClient()
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        return (AppModel(client: client, store: store), client)
    }

    @Test func loadBranchesPopulatesStateOnResult() async {
        let (model, client) = makeModelWithFakeClient()
        await model.loadBranches(repoPath: "/tmp/r")
        #expect(model.branchesLoading == true)
        // Simulate Mac response: get the last sent commandId
        let cid = client.commands.last!.commandId
        model.handle(.commandResult(CommandResult(commandId: cid, ok: true, error: nil, branches: ["main", "dev"])))
        #expect(model.branchesForRepo == ["main", "dev"])
        #expect(model.branchesLoading == false)
    }

    @Test func loadBranchesFailureSetsError() async {
        let (model, client) = makeModelWithFakeClient()
        await model.loadBranches(repoPath: "/tmp/r")
        #expect(model.branchesLoading == true)
        let cid = client.commands.last!.commandId
        model.handle(.commandResult(CommandResult(commandId: cid, ok: false, error: "unknown_repo", branches: nil)))
        #expect(model.branchesLoading == false)
        #expect(model.branchesForRepo == [])
        #expect(model.branchesError == "unknown_repo")
    }
}
