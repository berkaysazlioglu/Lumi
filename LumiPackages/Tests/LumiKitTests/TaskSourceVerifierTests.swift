import Foundation
import LumiTestSupport
import XCTest

@testable import LumiKit

/// Verify kontrol listesi: adapter'dan bağımsız, yazma testleri yalnız kendi
/// test task'inde, başarısızlıklar ajan raporuna düşer.
@MainActor
final class TaskSourceVerifierTests: XCTestCase {
    private func outcomes(_ report: TaskVerificationReport) -> [TaskVerificationStep.Kind: TaskVerificationStep.Outcome] {
        Dictionary(uniqueKeysWithValues: report.steps.map { ($0.kind, $0.outcome) })
    }

    func testFullSourcePassesEveryStepAndCleansUp() async {
        let provider = FakeTaskProvider(tasks: [.fake(id: "1")], users: [TaskUser(id: "u", name: "U")])
        var updates = 0
        let report = await TaskSourceVerifier.run(provider) { _ in updates += 1 }

        XCTAssertTrue(report.canConnect)
        XCTAssertFalse(report.hasFailure)
        XCTAssertGreaterThan(updates, TaskVerificationStep.Kind.allCases.count, "adımlar canlı bildirilir")
        let created = await provider.created
        let deleted = await provider.deleted
        let tasks = await provider.tasks
        XCTAssertEqual(created.map(\.title), [TaskSourceVerifier.testTaskTitle])
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(tasks.map(\.id), ["1"], "kullanıcının task'lerine dokunulmaz")
    }

    func testDiscoveryFailureSkipsTheRest() async {
        let provider = FakeTaskProvider()
        await provider.setDiscoverError(.unauthorized)
        let report = await TaskSourceVerifier.run(provider) { _ in }

        XCTAssertFalse(report.canConnect)
        XCTAssertTrue(outcomes(report)[.discovery]?.isFailure == true)
        XCTAssertEqual(outcomes(report)[.listTasks], .skipped("Needs a successful connection"))
        XCTAssertTrue(report.agentReport.contains("FAILED · Connect and authenticate"))
        let listCount = await provider.listCount
        XCTAssertEqual(listCount, 0)
    }

    func testNewerProtocolVersionFails() async {
        let provider = FakeTaskProvider(info: TaskSourceInfo(version: 2))
        let report = await TaskSourceVerifier.run(provider) { _ in }
        XCTAssertTrue(outcomes(report)[.version]?.isFailure == true)
        XCTAssertFalse(report.canConnect)
    }

    func testMinimalSourceSkipsOptionalStepsButCanConnect() async {
        let provider = FakeTaskProvider(info: TaskSourceInfo())
        let report = await TaskSourceVerifier.run(provider) { _ in }

        XCTAssertTrue(report.canConnect, "discovery + liste minimum uyumlu sunucudur")
        if case .skipped = outcomes(report)[.create] {} else { XCTFail("create beyan edilmedi") }
        if case .skipped = outcomes(report)[.listUsers] {} else { XCTFail("users beyan edilmedi") }
        let updates = await provider.updates
        XCTAssertTrue(updates.isEmpty, "create yoksa gerçek task üzerinde yazma denenmez")
    }

    func testCreateWithoutDeleteWarnsAboutLeftover() async {
        let provider = FakeTaskProvider(info: TaskSourceInfo(capabilities: [.create]))
        let report = await TaskSourceVerifier.run(provider) { _ in }

        XCTAssertTrue(report.canConnect)
        if case .warning = outcomes(report)[.delete] {} else { XCTFail("artık task uyarısı bekleniyordu") }
        XCTAssertTrue(report.agentReport.contains("WARNING"))
    }

    func testListFailureBlocksConnecting() async {
        let provider = FakeTaskProvider()
        await provider.setListError(.invalidResponse("not JSON"))
        let report = await TaskSourceVerifier.run(provider) { _ in }
        XCTAssertFalse(report.canConnect)
        XCTAssertTrue(report.agentReport.contains("not JSON"))
    }
}
