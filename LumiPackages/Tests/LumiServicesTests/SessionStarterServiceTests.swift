import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiServices

/// Refactor 3.1: enjekte edilen `ProcessRunning`/`BinaryLocating` sayesinde
/// `claude` binary'si olmadan tam davranış testi.
final class SessionStarterServiceTests: XCTestCase {
    private func makeService(
        runner: FakeProcessRunner,
        locator: FakeBinaryLocator
    ) -> SessionStarterService {
        SessionStarterService(binaryName: "claude", runner: runner, locator: locator)
    }

    func testThrowsCLINotFoundWhenBinaryMissing() async {
        let runner = FakeProcessRunner()
        let service = makeService(runner: runner, locator: FakeBinaryLocator())

        await assertThrows(.cliNotFound(binary: "claude")) {
            try await service.start(prompt: "merhaba")
        }
        let invocations = await runner.invocations
        XCTAssertTrue(invocations.isEmpty, "binary yokken hiç process açılmamalı")
    }

    func testSpawnsBinaryWithPromptAsSingleArgument() async throws {
        let runner = FakeProcessRunner()
        await runner.stub(commandLine: "/opt/bin/claude -p bir iki üç", with: .success("ok"))
        let locator = FakeBinaryLocator(paths: ["claude": "/opt/bin/claude"])

        try await makeService(runner: runner, locator: locator).start(prompt: "bir iki üç")

        let invocations = await runner.invocations
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations.first?.executable, "/opt/bin/claude")
        // Shell yok: prompt tek argv olarak geçer (boşluklar bölünmez).
        XCTAssertEqual(invocations.first?.arguments, ["-p", "bir iki üç"])
        XCTAssertEqual(invocations.first?.timeout, SessionStarterService.startTimeout)
    }

    func testTimeoutBecomesSessionStartFailed() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.timeout)
        let locator = FakeBinaryLocator(paths: ["claude": "/opt/bin/claude"])

        await assertThrows(
            .sessionStartFailed(detail: "claude -p timed out or failed to launch")
        ) {
            try await self.makeService(runner: runner, locator: locator).start(prompt: "x")
        }
    }

    func testNonZeroExitReportsStderr() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 2, stderr: "  not logged in\n"))
        let locator = FakeBinaryLocator(paths: ["claude": "/opt/bin/claude"])

        await assertThrows(.sessionStartFailed(detail: "not logged in")) {
            try await self.makeService(runner: runner, locator: locator).start(prompt: "x")
        }
    }

    func testNonZeroExitWithEmptyStderrFallsBackToExitCode() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 7))
        let locator = FakeBinaryLocator(paths: ["claude": "/opt/bin/claude"])

        await assertThrows(.sessionStartFailed(detail: "exit code 7")) {
            try await self.makeService(runner: runner, locator: locator).start(prompt: "x")
        }
    }

    // MARK: - Yardımcı

    private func assertThrows(
        _ expected: LumiError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("hata bekleniyordu", file: file, line: line)
        } catch let error as LumiError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("beklenmeyen hata tipi: \(error)", file: file, line: line)
        }
    }
}
