import XCTest
@testable import LumiMobileKit

/// Decision 132: reorder + appearance edits from the phone.
@MainActor
final class ProjectEditsTests: XCTestCase {
    private func project(_ path: String, appearance: ProjectAppearance = .none) -> ProjectNode {
        ProjectNode(name: path, path: path, checkouts: [], appearance: appearance)
    }

    private func snapshot(_ projects: [ProjectNode]) -> ProjectsSnapshot {
        ProjectsSnapshot(projects: projects, addable: [])
    }

    private func makeModel(_ paths: [String]) -> (AppModel, FakeRelayClient) {
        let store = InMemorySecureStore()
        store.write(PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef"))
        let client = FakeRelayClient()
        let model = AppModel(client: client, store: store)
        model.handle(.projects(snapshot(paths.map { project($0) })))
        return (model, client)
    }

    private func shown(_ model: AppModel) -> [String] { model.projectTree.map(\.id) }

    // MARK: - Reorder

    func testMoveIsOptimisticAndSendsFullOrder() async {
        let (model, client) = makeModel(["/a", "/b", "/c"])
        await model.moveProject("/a", onto: "/c")
        XCTAssertEqual(shown(model), ["/b", "/c", "/a"])
        guard case .reorderProjects(let paths) = client.commands.last?.action else { return XCTFail("no reorder") }
        XCTAssertEqual(paths, ["/b", "/c", "/a"])
    }

    func testStaleSnapshotDoesNotUndoUnconfirmedMove() async {
        let (model, _) = makeModel(["/a", "/b", "/c"])
        await model.moveProject("/a", onto: "/c")
        model.handle(.projects(snapshot([project("/a"), project("/b"), project("/c")])))
        XCTAssertEqual(shown(model), ["/b", "/c", "/a"])
        XCTAssertFalse(model.pendingProjectEdits.isEmpty)
    }

    func testMatchingSnapshotClearsPendingOrder() async {
        let (model, _) = makeModel(["/a", "/b", "/c"])
        await model.moveProject("/a", onto: "/c")
        model.handle(.projects(snapshot([project("/b"), project("/c"), project("/a")])))
        XCTAssertTrue(model.pendingProjectEdits.isEmpty)
    }

    func testConfirmedMoveYieldsToNextSnapshot() async {
        let (model, client) = makeModel(["/a", "/b", "/c"])
        await model.moveProject("/a", onto: "/c")
        let id = client.commands.last!.commandId
        model.handle(.commandResult(CommandResult(commandId: id, ok: true, error: nil)))
        // The Mac's next snapshot is the truth, whatever it says.
        model.handle(.projects(snapshot([project("/c"), project("/a"), project("/b")])))
        XCTAssertEqual(shown(model), ["/c", "/a", "/b"])
    }

    func testRejectedMoveRestoresMacOrderAndReportsError() async {
        let (model, client) = makeModel(["/a", "/b", "/c"])
        await model.moveProject("/a", onto: "/c")
        let id = client.commands.last!.commandId
        model.handle(.commandResult(CommandResult(commandId: id, ok: false, error: "invalid_order")))
        XCTAssertEqual(shown(model), ["/a", "/b", "/c"])
        XCTAssertEqual(model.projectEditError, "invalid_order")
        model.clearProjectEditError()
        XCTAssertNil(model.projectEditError)
    }

    func testMoveOntoItselfSendsNothing() async {
        let (model, client) = makeModel(["/a", "/b"])
        await model.moveProject("/a", onto: "/a")
        XCTAssertTrue(client.commands.isEmpty)
    }

    func testUnsentMoveRollsBack() async {
        let (model, client) = makeModel(["/a", "/b"])
        client.sendResult = false
        await model.moveProject("/a", onto: "/b")
        XCTAssertEqual(shown(model), ["/a", "/b"])
        XCTAssertEqual(model.projectEditError, "no connection")
    }

    // MARK: - Appearance

    func testAppearanceIsOptimisticAndEncodedForTheMac() async {
        let (model, client) = makeModel(["/a"])
        let appearance = ProjectAppearance(color: .pink, icon: .emoji("🚀"), rootTitle: "dev")
        await model.setProjectAppearance(path: "/a", appearance: appearance)
        XCTAssertEqual(model.projectTree.first?.node.appearance, appearance)
        let frame = PhoneProtocol.commandFrame(client.commands.last!)
        XCTAssertTrue(frame.contains("\"action\":\"set_project_appearance\""))
        XCTAssertTrue(frame.contains("\"color\":\"pink\""))
        XCTAssertTrue(frame.contains("\"icon\":\"emoji:🚀\""))
        XCTAssertTrue(frame.contains("\"rootTitle\":\"dev\""))
    }

    func testClearedAppearanceOmitsFields() async {
        let (model, client) = makeModel(["/a"])
        await model.setProjectAppearance(path: "/a", appearance: .none)
        let frame = PhoneProtocol.commandFrame(client.commands.last!)
        XCTAssertFalse(frame.contains("\"color\""))
        XCTAssertFalse(frame.contains("\"icon\""))
        XCTAssertFalse(frame.contains("\"rootTitle\""))
    }

    func testAppearanceClearsWhenSnapshotShowsIt() async {
        let (model, _) = makeModel(["/a"])
        let appearance = ProjectAppearance(color: .teal)
        await model.setProjectAppearance(path: "/a", appearance: appearance)
        model.handle(.projects(snapshot([project("/a", appearance: appearance)])))
        XCTAssertTrue(model.pendingProjectEdits.isEmpty)
    }

    func testRejectedAppearanceRestoresMacValue() async {
        let (model, client) = makeModel(["/a"])
        await model.setProjectAppearance(path: "/a", appearance: ProjectAppearance(color: .teal))
        let id = client.commands.last!.commandId
        model.handle(.commandResult(CommandResult(commandId: id, ok: false, error: "invalid_icon")))
        XCTAssertEqual(model.projectTree.first?.node.appearance, ProjectAppearance.none)
        XCTAssertEqual(model.projectEditError, "invalid_icon")
    }
}
