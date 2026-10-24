import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiRemote

/// Telefondaki Tasks komutları (karar 137 mobil ek) köprüye yönlenir.
@MainActor
final class RemoteTaskCommandRoutingTests: XCTestCase {
    private final class Recorder: RemoteTasksHandling {
        var calls: [(String, [String: Any])] = []
        var outcome = RemoteTaskCommandOutcome(ok: true, data: ["body": "hello"])

        func handleTaskCommand(action: String, payload: [String: Any]) async -> RemoteTaskCommandOutcome {
            calls.append((action, payload))
            return outcome
        }
    }

    private func handler() -> RemoteCommandHandler {
        RemoteCommandHandler(terminal: FakeTerminalService(), trust: NoopClaudeWorkspaceTrust(), config: FakeConfigService())
    }

    func testTaskActionsReachTheBridgeWithData() async {
        let handler = handler()
        let recorder = Recorder()
        handler.tasks = recorder

        let result = await handler.handle(["commandId": "c1", "action": "task_detail", "sourceId": "s", "taskId": "1"])
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.payload["data"] as? [String: String], ["body": "hello"])
        XCTAssertEqual(recorder.calls.map(\.0), ["task_detail"])

        recorder.outcome = .failure("no_project")
        let failed = await handler.handle(["commandId": "c2", "action": "task_start"])
        XCTAssertFalse(failed.ok)
        XCTAssertEqual(failed.error, "no_project")
        _ = await handler.handle(["commandId": "c3", "action": "tasks_subscribe"])
        XCTAssertEqual(recorder.calls.map(\.0), ["task_detail", "task_start", "tasks_subscribe"])
    }

    func testWithoutBridgeTasksAreUnavailable() async {
        let result = await handler().handle(["commandId": "c1", "action": "task_move"])
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "tasks_unavailable")
    }
}
