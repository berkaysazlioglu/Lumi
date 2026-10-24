import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Gerçek bir Lumi Tasks sunucusuna karşı uçtan uca kontrol (Tasks planı,
/// Faz 2 dogfood). Yalnız `LUMI_TASKS_E2E_URL` ve `LUMI_TASKS_E2E_TOKEN`
/// tanımlıysa koşar; CI'da atlanır.
///
///     LUMI_TASKS_E2E_URL=http://localhost:4100 LUMI_TASKS_E2E_TOKEN=… \
///       swift test --filter LumiTasksLiveServerTests
@MainActor
final class LumiTasksLiveServerTests: XCTestCase {
    private func provider(token: String? = nil) throws -> LumiTasksHTTPProvider {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["LUMI_TASKS_E2E_URL"], let secret = environment["LUMI_TASKS_E2E_TOKEN"],
              case .success(let url) = TaskEndpoint.normalize(address)
        else { throw XCTSkip("LUMI_TASKS_E2E_URL / LUMI_TASKS_E2E_TOKEN not set") }
        return LumiTasksHTTPProvider(baseURL: url, token: token ?? secret, transport: URLSessionTransport())
    }

    func testVerifierPassesAgainstServer() async throws {
        let report = await TaskSourceVerifier.run(try provider()) { _ in }
        for step in report.steps { print("verify:", step.kind.rawValue, step.outcome) }
        XCTAssertTrue(report.canConnect, report.agentReport)
        XCTAssertFalse(report.hasFailure, report.agentReport)
    }

    func testWrongTokenIsRejectedWithEnvelope() async throws {
        do {
            _ = try await provider(token: "wrong").discover()
            XCTFail("wrong token accepted")
        } catch let failure as TaskRequestFailure {
            print("401 failure:", failure.summary)
            XCTAssertEqual(failure.kind, .unauthorized)
            XCTAssertEqual(failure.httpStatus, 401)
            XCTAssertEqual(failure.request, "GET /lumi/v1")
            XCTAssertNotNil(failure.serverMessage)
        }
    }

    func testInvalidStatusComesBackAs422WithServerMessage() async throws {
        let provider = try provider()
        let info = try await provider.discover()
        guard info.supports(.create), info.supports(.delete) else { throw XCTSkip("needs create + delete") }
        let task = try await provider.create(TaskDraft(title: "[Lumi e2e] invalid status"))
        defer { Task { try? await provider.delete(taskID: task.id) } }

        // Gerçek istemci geçersiz durum gönderemez; ham istekle sınanır.
        var request = URLRequest(url: URL(string: ProcessInfo.processInfo.environment["LUMI_TASKS_E2E_URL"]! + "/lumi/v1/tasks/\(task.id)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(ProcessInfo.processInfo.environment["LUMI_TASKS_E2E_TOKEN"]!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"status":"blocked"}"#.utf8)
        let response = try await URLSessionTransport().send(request)
        XCTAssertEqual(response.status, 422)
        XCTAssertEqual(LumiTasksWire.envelope(try JSONSerialization.jsonObject(with: response.body)).code, "validation_failed")

        let moved = try await provider.update(taskID: task.id, patch: TaskPatch(status: .done, priority: .high))
        XCTAssertEqual(moved.status, .done)
        XCTAssertGreaterThan(moved.updatedAt, task.updatedAt)
        try await provider.delete(taskID: task.id)
        do {
            _ = try await provider.update(taskID: task.id, patch: TaskPatch(status: .todo))
            XCTFail("deleted task updated")
        } catch let failure as TaskRequestFailure {
            XCTAssertEqual(failure.kind, .notFound)
        }
    }
}
