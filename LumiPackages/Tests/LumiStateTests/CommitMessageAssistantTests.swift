import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

@MainActor
final class CommitMessageAssistantTests: XCTestCase {
    private let path = "/tmp/lumi-assistant"
    private let request = CommitMessageRequest(vcsName: "Git", changes: [.init(path: "a", status: .modified)])

    func testGenerateReturnsMessageAndClearsInFlightFlag() async {
        let generator = FakeCommitMessageGenerator()
        await generator.setMessage("Fix crash on launch")
        let assistant = CommitMessageAssistant(generator: generator, toasts: ToastStore(autoDismissAfter: 60))

        let message = await assistant.generate(path, request: request)

        XCTAssertEqual(message, "Fix crash on launch")
        XCTAssertFalse(assistant.isGenerating(path))
        let requests = await generator.requests
        XCTAssertEqual(requests, [request])
    }

    func testFailureShowsToastAndReturnsNil() async {
        let generator = FakeCommitMessageGenerator()
        await generator.setError(.cliNotFound(binary: "claude"))
        let toasts = ToastStore(autoDismissAfter: 60)
        let assistant = CommitMessageAssistant(generator: generator, toasts: toasts)

        let message = await assistant.generate(path, request: request)

        XCTAssertNil(message)
        XCTAssertEqual(toasts.toasts.count, 1)
    }

    func testEmptySelectionIsReportedWithoutCallingGenerator() async {
        let generator = FakeCommitMessageGenerator()
        let toasts = ToastStore(autoDismissAfter: 60)
        let assistant = CommitMessageAssistant(generator: generator, toasts: toasts)

        let message = await assistant.generate(path, request: CommitMessageRequest(vcsName: "Git", changes: []))

        XCTAssertNil(message)
        XCTAssertEqual(toasts.toasts.count, 1)
        let requests = await generator.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testSecondRequestWhileInFlightIsIgnored() async {
        let generator = FakeCommitMessageGenerator()
        await generator.setDelay(.milliseconds(50))
        let assistant = CommitMessageAssistant(generator: generator, toasts: ToastStore(autoDismissAfter: 60))

        let first = Task { await assistant.generate(path, request: request) }
        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertTrue(assistant.isGenerating(path))
        let second = await assistant.generate(path, request: request)
        let firstResult = await first.value

        XCTAssertNil(second)
        XCTAssertEqual(firstResult, "Update files")
        let requests = await generator.requests
        XCTAssertEqual(requests.count, 1)
    }
}
