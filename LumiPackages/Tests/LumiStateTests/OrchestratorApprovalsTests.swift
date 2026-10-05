import Foundation
import LumiKit
import XCTest
@testable import LumiState

/// Karar 114 Faz 3: yazma eylemlerinin onay kapısı.
@MainActor
final class OrchestratorApprovalsTests: XCTestCase {
    private func request(_ title: String = "Send") -> OrchestratorApprovalRequest {
        OrchestratorApprovalRequest(kind: .sendMessage, title: title, target: "api · claude", body: "merhaba")
    }

    /// İsteği başlatır ve kart görünene kadar bekler.
    private func start(
        _ approvals: OrchestratorApprovals, _ request: OrchestratorApprovalRequest
    ) async -> Task<OrchestratorApprovals.Decision, Never> {
        let task = Task { await approvals.request(request) }
        while !approvals.pending.contains(where: { $0.id == request.id }) { await Task.yield() }
        return task
    }

    func testApproveAndRejectResolveTheirOwnRequest() async {
        let approvals = OrchestratorApprovals()
        let first = request("a")
        let second = request("b")
        let a = await start(approvals, first)
        let b = await start(approvals, second)
        XCTAssertEqual(approvals.pending.map(\.title), ["a", "b"])

        approvals.reject(second.id)
        approvals.approve(first.id)

        let decisionA = await a.value
        let decisionB = await b.value
        XCTAssertEqual(decisionA, .approved)
        XCTAssertEqual(decisionB, .rejected)
        XCTAssertTrue(approvals.pending.isEmpty)
    }

    func testUnansweredRequestTimesOut() async {
        let approvals = OrchestratorApprovals(timeout: .milliseconds(30))
        let task = await start(approvals, request())
        let decision = await task.value
        XCTAssertEqual(decision, .timedOut)
        XCTAssertTrue(approvals.pending.isEmpty)
    }

    func testRejectAllClearsEveryCard() async {
        let approvals = OrchestratorApprovals()
        let a = await start(approvals, request("a"))
        let b = await start(approvals, request("b"))

        approvals.rejectAll()

        let decisionA = await a.value
        let decisionB = await b.value
        XCTAssertEqual([decisionA, decisionB], [.rejected, .rejected])
        XCTAssertTrue(approvals.pending.isEmpty)
    }

    func testSecondAnswerIsIgnored() async {
        let approvals = OrchestratorApprovals()
        let req = request()
        let task = await start(approvals, req)
        approvals.approve(req.id)
        approvals.reject(req.id)
        let decision = await task.value
        XCTAssertEqual(decision, .approved)
    }
}
