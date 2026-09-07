import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

final class ClaudeCommitMessageServiceTests: XCTestCase {
    private let claude = "/Users/me/.local/bin/claude"
    private let request = CommitMessageRequest(vcsName: "Git", changes: [.init(path: "a.swift", status: .modified)], diff: "+x")

    private func makeService(runner: FakeProcessRunner, installed: Bool = true) -> ClaudeCommitMessageService {
        ClaudeCommitMessageService(
            runner: runner,
            locator: FakeBinaryLocator(paths: installed ? ["claude": claude] : [:]),
            workingDirectory: "/tmp/lumi-scratch"
        )
    }

    private static let successJSON = #"{"type":"result","subtype":"success","is_error":false,"result":"Update a.swift\n"}"#

    func testRunsHeadlessLowEffortToollessClaudeWithBodyOnStdin() async throws {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(Self.successJSON))
        let service = makeService(runner: runner)

        let message = try await service.generate(request)

        XCTAssertEqual(message, "Update a.swift")
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, claude)
        XCTAssertEqual(invocation?.arguments, [
            "-p", CommitMessagePrompt.instruction(vcsName: "Git"),
            "--model", "sonnet", "--effort", "low", "--output-format", "json",
            "--tools", "", "--setting-sources", "", "--no-session-persistence",
        ])
        XCTAssertEqual(invocation?.currentDirectory, "/tmp/lumi-scratch", "proje CLAUDE.md'leri yüklenmesin")
        XCTAssertEqual(invocation?.standardInput, Data(CommitMessagePrompt.body(for: request).utf8))
        XCTAssertEqual(invocation?.timeout, ClaudeCommitMessageService.timeout)
        XCTAssertFalse(invocation?.arguments.contains("--bare") ?? true, "--bare keychain'i atlar → Not logged in")
    }

    func testMissingCLIThrowsCLINotFoundWithoutSpawning() async {
        let runner = FakeProcessRunner()
        let service = makeService(runner: runner, installed: false)
        do {
            _ = try await service.generate(request)
            XCTFail("hata bekleniyordu")
        } catch let error as LumiError {
            guard case .cliNotFound(let binary) = error else { return XCTFail("beklenmeyen: \(error)") }
            XCTAssertEqual(binary, "claude")
        } catch { XCTFail("beklenmeyen: \(error)") }
        let invocations = await runner.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testNonZeroExitSurfacesStderrAndEmptyReplyFails() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 1, stderr: "Not logged in · Please run /login\n"))
        let service = makeService(runner: runner)
        do {
            _ = try await service.generate(request)
            XCTFail("hata bekleniyordu")
        } catch let error as LumiError {
            guard case .commitMessageGenerationFailed(let detail) = error else { return XCTFail("beklenmeyen: \(error)") }
            XCTAssertEqual(detail, "Not logged in · Please run /login")
        } catch { XCTFail("beklenmeyen: \(error)") }

        await runner.setDefaultResult(.success(#"{"type":"result","subtype":"success","is_error":false,"result":"\n\n"}"#))
        do {
            _ = try await service.generate(request)
            XCTFail("boş yanıt hata olmalı")
        } catch let error as LumiError {
            guard case .commitMessageGenerationFailed(let detail) = error else { return XCTFail("beklenmeyen: \(error)") }
            XCTAssertEqual(detail, "empty reply")
        } catch { XCTFail("beklenmeyen: \(error)") }
    }

    func testJSONEnvelopeErrorsAndGarbageAreReported() throws {
        XCTAssertEqual(try ClaudeCommitMessageService.resultText(fromJSON: #"{"type":"result","result":"Fix it"}"#), "Fix it")
        XCTAssertThrowsError(try ClaudeCommitMessageService.resultText(fromJSON: #"{"type":"result","is_error":true,"result":"Not logged in"}"#)) { error in
            guard case .commitMessageGenerationFailed(let detail)? = error as? LumiError else { return XCTFail("beklenmeyen: \(error)") }
            XCTAssertEqual(detail, "Not logged in")
        }
        XCTAssertThrowsError(try ClaudeCommitMessageService.resultText(fromJSON: "not json"))
    }

    func testEmptySelectionFailsBeforeLocatingBinary() async {
        let runner = FakeProcessRunner()
        let service = makeService(runner: runner, installed: false)
        do {
            _ = try await service.generate(CommitMessageRequest(vcsName: "Git", changes: []))
            XCTFail("hata bekleniyordu")
        } catch let error as LumiError {
            guard case .commitMessageGenerationFailed = error else { return XCTFail("beklenmeyen: \(error)") }
        } catch { XCTFail("beklenmeyen: \(error)") }
    }
}
