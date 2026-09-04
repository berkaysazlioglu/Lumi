import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiServices

/// Refactor 3.9: `SystemService` artık `[any SystemCheck]` koşturur.
/// design/02 §8'in fail/warn ayrımı ve kontrol sırası burada kilitlenir.
final class SystemChecksTests: XCTestCase {
    private struct FailingSmokeTester: TerminalSmokeTesting {
        func runSmokeTest() async throws {
            throw LumiError.spawnFailed(reason: "no pty")
        }
    }

    private struct PassingSmokeTester: TerminalSmokeTesting {
        func runSmokeTest() async throws {}
    }

    private func service(
        locator: FakeBinaryLocator,
        smokeTester: (any TerminalSmokeTesting)? = nil
    ) -> SystemService {
        SystemService(checks: SystemService.defaultChecks(
            smokeTester: smokeTester, locator: locator
        ))
    }

    // MARK: - CLI kontrolü: seçili sağlayıcı FAIL, diğeri WARN

    func testMissingSelectedProviderCLIFailsAndIsFixable() async {
        let locator = FakeBinaryLocator(paths: [:])
        let results = await service(locator: locator).runChecks(selectedProvider: .claude)

        let claude = try? XCTUnwrap(results.first { $0.id == "claude-cli" })
        XCTAssertEqual(claude?.status, .fail)
        XCTAssertEqual(claude?.isFixable, true)
        XCTAssertEqual(claude?.message, "claude not found in PATH")
    }

    func testMissingUnselectedProviderCLIOnlyWarnsAndIsNotFixable() async {
        let locator = FakeBinaryLocator(paths: [:])
        let results = await service(locator: locator).runChecks(selectedProvider: .claude)

        let codex = try? XCTUnwrap(results.first { $0.id == "codex-cli" })
        XCTAssertEqual(codex?.status, .warn)
        XCTAssertEqual(codex?.isFixable, false)
    }

    func testSelectedProviderSwitchesWhichCheckFails() async {
        let locator = FakeBinaryLocator(paths: [:])
        let results = await service(locator: locator).runChecks(selectedProvider: .codex)

        XCTAssertEqual(results.first { $0.id == "codex-cli" }?.status, .fail)
        XCTAssertEqual(results.first { $0.id == "claude-cli" }?.status, .warn)
    }

    func testFoundBinaryPassesWithItsPath() async {
        let locator = FakeBinaryLocator(paths: ["claude": "/opt/bin/claude"])
        let results = await service(locator: locator).runChecks(selectedProvider: .claude)

        let claude = try? XCTUnwrap(results.first { $0.id == "claude-cli" })
        XCTAssertEqual(claude?.status, .pass)
        XCTAssertEqual(claude?.message, "/opt/bin/claude")
    }

    // MARK: - PTY kontrolü yalnız smoke tester verilmişse

    func testPTYCheckIsAbsentWithoutSmokeTester() async {
        let results = await service(locator: FakeBinaryLocator())
            .runChecks(selectedProvider: .claude)

        XCTAssertFalse(results.contains { $0.id == "pty" })
    }

    func testPTYCheckFailsWhenSmokeTestThrows() async {
        let results = await service(
            locator: FakeBinaryLocator(), smokeTester: FailingSmokeTester()
        ).runChecks(selectedProvider: .claude)

        let pty = try? XCTUnwrap(results.first { $0.id == "pty" })
        XCTAssertEqual(pty?.status, .fail)
        XCTAssertTrue(pty?.message.hasPrefix("PTY smoke test failed:") == true)
    }

    func testCheckOrderIsShellThenPTYThenProviderCLIs() async {
        let results = await service(
            locator: FakeBinaryLocator(), smokeTester: PassingSmokeTester()
        ).runChecks(selectedProvider: .claude)

        XCTAssertEqual(results.map(\.id), ["shell", "pty", "claude-cli", "codex-cli"])
    }

    // MARK: - Shell kontrolü

    func testShellCheckFailsWhenNoShellIsExecutable() async {
        let check = ShellCheck(isExecutableFile: { _ in false })
        let result = await check.run(context: SystemCheckContext(selectedProvider: .claude))

        XCTAssertEqual(result.status, .fail)
        XCTAssertEqual(result.message, "No usable shell found (zsh/bash/sh)")
    }

    func testShellCheckPrefersFirstAvailableCandidate() async {
        let check = ShellCheck(isExecutableFile: { $0 != "/bin/zsh" })
        let result = await check.run(context: SystemCheckContext(selectedProvider: .claude))

        XCTAssertEqual(result.status, .pass)
        XCTAssertEqual(result.message, "/bin/bash")
    }
}
