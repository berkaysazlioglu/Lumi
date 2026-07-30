import Foundation
import LumiKit
import XCTest
@testable import LumiRemote

/// Adapter testleri için minimal TerminalServicing fake'i.
@MainActor
private final class FakeTerminalService: TerminalServicing {
    private let broadcaster = EventBroadcaster<TerminalEvent>()
    var terminals: [TerminalMeta] = []
    var screenSnapshots: [TerminalID: TerminalScreenSnapshot] = [:]
    private(set) var writtenTexts: [(id: TerminalID, text: String)] = []

    @discardableResult
    func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        let meta = TerminalMeta(
            id: TerminalID(), name: "T", repoPath: repoPath, createdAt: Date(), task: task
        )
        terminals.append(meta)
        return meta
    }

    func write(id: TerminalID, text: String) throws {
        guard terminals.contains(where: { $0.id == id }) else {
            throw LumiError.terminalNotFound(id)
        }
        writtenTexts.append((id, text))
    }

    func kill(id: TerminalID) throws {}
    func killAll() {}
    func resize(id: TerminalID, cols: Int, rows: Int) {}
    func setFocused(_ id: TerminalID?) {}
    func setWindowFocused(_ focused: Bool) {}
    func setMaxTerminals(_ n: Int) {}
    func events() -> AsyncStream<TerminalEvent> { broadcaster.stream() }
    func outputStream(id: TerminalID) -> AsyncStream<String>? {
        terminals.contains { $0.id == id } ? AsyncStream { _ in } : nil
    }
    func screenSnapshot(id: TerminalID) -> TerminalScreenSnapshot? { screenSnapshots[id] }
}

@MainActor
final class TerminalServiceRemoteAdapterTests: XCTestCase {
    private func makeFixture() throws -> (FakeTerminalService, TerminalServiceRemoteAdapter, TerminalMeta) {
        let service = FakeTerminalService()
        let meta = try service.spawn(repoPath: "/tmp/proj", task: "Claude", command: nil)
        return (service, TerminalServiceRemoteAdapter(service: service), meta)
    }

    func testListTerminalsMapsMetaToSummary() async throws {
        let (_, adapter, meta) = try makeFixture()

        let summaries = await adapter.listTerminals()

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].id, meta.id.raw.uuidString)
        XCTAssertEqual(summaries[0].repoName, "proj")
        XCTAssertEqual(summaries[0].status, TerminalStatus.idle.rawValue)
    }

    func testScreenSnapshotResolvesStringID() async throws {
        let (service, adapter, meta) = try makeFixture()
        let snapshot = TerminalScreenSnapshot(
            history: "ekran",
            screen: [[TerminalScreenRun(text: "satır", foreground: "#ff0000", flags: 1)]]
        )
        service.screenSnapshots[meta.id] = snapshot

        let resolved = await adapter.screenSnapshot(id: meta.id.raw.uuidString)

        XCTAssertEqual(resolved, snapshot)
    }

    func testSendInputWritesRawText() async throws {
        let (service, adapter, meta) = try makeFixture()

        let ok = await adapter.sendInput(id: meta.id.raw.uuidString, rawText: "\u{1B}[B")

        XCTAssertTrue(ok)
        let written = service.writtenTexts
        XCTAssertEqual(written.map(\.text), ["\u{1B}[B"])
    }

    func testSendPromptWrapsWithBracketedPaste() async throws {
        let (service, adapter, meta) = try makeFixture()

        let ok = await adapter.sendPrompt(id: meta.id.raw.uuidString, prompt: "satır1\nsatır2\n")

        XCTAssertTrue(ok)
        let written = service.writtenTexts
        XCTAssertEqual(written.map(\.text), [PromptInjection.encode("satır1\nsatır2\n")])
        XCTAssertTrue(written[0].text.hasPrefix(PromptInjection.pasteStart))
        XCTAssertTrue(written[0].text.hasSuffix(PromptInjection.submit))
    }

    func testEmptyPromptIsRejected() async throws {
        let (service, adapter, meta) = try makeFixture()

        let ok = await adapter.sendPrompt(id: meta.id.raw.uuidString, prompt: "")

        XCTAssertFalse(ok)
        let written = service.writtenTexts
        XCTAssertTrue(written.isEmpty)
    }

    func testInvalidOrUnknownIDsFailGracefully() async throws {
        let (_, adapter, _) = try makeFixture()
        let unknown = UUID().uuidString

        let inputOK = await adapter.sendInput(id: "not-a-uuid", rawText: "x")
        let unknownOK = await adapter.sendInput(id: unknown, rawText: "x")

        XCTAssertFalse(inputOK)
        XCTAssertFalse(unknownOK)
        let screen = await adapter.screenSnapshot(id: "not-a-uuid")
        XCTAssertNil(screen)
        let terminal = await adapter.terminal(id: unknown)
        XCTAssertNil(terminal)
        let signal = await adapter.outputSignal(id: unknown)
        XCTAssertNil(signal)
    }
}
