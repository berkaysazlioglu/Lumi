import XCTest
@testable import LumiRemote

final class TerminalSocketSessionTests: XCTestCase {
    private let terminalID = "11111111-1111-1111-1111-111111111111"

    private func makeSession(
        provider: FakeRemoteProvider
    ) -> (TerminalSocketSession, SentMessageCollector) {
        let collector = SentMessageCollector()
        let session = TerminalSocketSession(
            provider: provider,
            send: { collector.append($0) },
            close: { collector.markClosed() }
        )
        return (session, collector)
    }

    private func attachMessage() -> String {
        #"{"type":"attach","id":"11111111-1111-1111-1111-111111111111"}"#
    }

    func testAttachSendsImmediateSnapshot() async {
        let provider = FakeRemoteProvider(
            summaries: [makeSummary(id: terminalID)],
            screens: [terminalID: makeSnapshot(history: "ekran içeriği")]
        )
        let (session, collector) = makeSession(provider: provider)

        await session.handle(attachMessage())

        XCTAssertEqual(collector.messages.count, 1)
        XCTAssertTrue(collector.messages[0].contains(#""type":"snapshot""#))
        XCTAssertTrue(collector.messages[0].contains("ekran içeriği"))
        await session.finish()
    }

    func testAttachToUnknownTerminalSendsErrorAndCloses() async {
        let provider = FakeRemoteProvider()
        let (session, collector) = makeSession(provider: provider)

        await session.handle(attachMessage())

        XCTAssertTrue(collector.messages.last?.contains(#""type":"error""#) ?? false)
        XCTAssertTrue(collector.isClosed)
        await session.finish()
    }

    func testInputBeforeAttachSendsError() async {
        let provider = FakeRemoteProvider()
        let (session, collector) = makeSession(provider: provider)

        await session.handle(#"{"type":"input","data":"x"}"#)

        XCTAssertTrue(collector.messages.last?.contains("Not attached") ?? false)
        await session.finish()
    }

    func testInputAndPromptAreForwardedToProvider() async {
        let provider = FakeRemoteProvider(
            summaries: [makeSummary(id: terminalID)],
            screens: [terminalID: makeSnapshot(history: "")]
        )
        let (session, _) = makeSession(provider: provider)
        await session.handle(attachMessage())

        await session.handle(#"{"type":"input","data":"\r"}"#)
        await session.handle(#"{"type":"prompt","text":"merhaba claude"}"#)

        let inputs = await provider.inputs
        let prompts = await provider.prompts
        XCTAssertEqual(inputs.map(\.rawText), ["\r"])
        XCTAssertEqual(prompts.map(\.prompt), ["merhaba claude"])
        await session.finish()
    }

    func testOutputSignalTriggersCoalescedSnapshot() async {
        let provider = FakeRemoteProvider(
            summaries: [makeSummary(id: terminalID)],
            screens: [terminalID: makeSnapshot(history: "ilk")]
        )
        let (session, collector) = makeSession(provider: provider)
        await session.handle(attachMessage())
        XCTAssertEqual(collector.messages.count, 1)

        await provider.setScreen(terminalID, "güncellendi")
        await provider.emitOutput(terminalID)
        await provider.emitOutput(terminalID)

        let delivered = await waitUntil {
            collector.messages.contains { $0.contains("güncellendi") }
        }
        XCTAssertTrue(delivered)
        // İki output sinyali tek snapshot'a coalesce edilir (attach + 1 güncelleme)
        XCTAssertEqual(collector.messages.count, 2)
        await session.finish()
    }

    func testStatusChangeWithoutOutputTriggersSnapshot() async {
        let provider = FakeRemoteProvider(
            summaries: [makeSummary(id: terminalID, status: "working")],
            screens: [terminalID: makeSnapshot(history: "ekran")]
        )
        let (session, collector) = makeSession(provider: provider)
        await session.handle(attachMessage())

        await provider.updateStatus(terminalID, to: "waiting-unseen")

        let delivered = await waitUntil {
            collector.messages.contains { $0.contains("waiting-unseen") }
        }
        XCTAssertTrue(delivered)
        await session.finish()
    }

    func testTerminalRemovalSendsExitedAndCloses() async {
        let provider = FakeRemoteProvider(
            summaries: [makeSummary(id: terminalID)],
            screens: [terminalID: makeSnapshot(history: "ekran")]
        )
        let (session, collector) = makeSession(provider: provider)
        await session.handle(attachMessage())

        await provider.removeTerminal(terminalID)
        await provider.emitOutput(terminalID)

        let exited = await waitUntil {
            collector.messages.contains { $0.contains(#""type":"exited""#) }
        }
        XCTAssertTrue(exited)
        XCTAssertTrue(collector.isClosed)
        await session.finish()
    }

    func testMalformedMessageSendsError() async {
        let provider = FakeRemoteProvider()
        let (session, collector) = makeSession(provider: provider)

        await session.handle("garbage")

        XCTAssertTrue(collector.messages.last?.contains(#""type":"error""#) ?? false)
        await session.finish()
    }
}
