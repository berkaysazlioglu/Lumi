import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

final class ClaudeQuickCommandServiceTests: XCTestCase {
    private let claude = "/Users/me/.local/bin/claude"
    private let request = QuickCommandGenerationRequest(
        projectPath: "/projects/game", projectName: "Game", description: "open unity here"
    )

    private func makeService(runner: FakeProcessRunner, installed: Bool = true) -> ClaudeQuickCommandService {
        ClaudeQuickCommandService(runner: runner, locator: FakeBinaryLocator(paths: installed ? ["claude": claude] : [:]))
    }

    private static func envelope(_ result: String, isError: Bool = false, subtype: String = "success") -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "type": "result", "subtype": subtype, "is_error": isError, "result": result,
        ])
        return String(decoding: data, as: UTF8.self)
    }

    private func expectFailure(_ service: ClaudeQuickCommandService, file: StaticString = #filePath, line: UInt = #line) async -> String? {
        do {
            _ = try await service.generate(request)
            XCTFail("hata bekleniyordu", file: file, line: line)
        } catch let error as LumiError {
            if case .quickCommandGenerationFailed(let detail) = error { return detail }
            XCTFail("beklenmeyen: \(error)", file: file, line: line)
        } catch { XCTFail("beklenmeyen: \(error)", file: file, line: line) }
        return nil
    }

    func testRunsToolEnabledSonnetInProjectWithRequestOnStdin() async throws {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(Self.envelope("Found a script.\n\n```sh\ncd \"{path}\"\nmake\n```\n")))
        let script = try await makeService(runner: runner).generate(request)

        XCTAssertEqual(script, "cd \"{path}\"\nmake\n", "only the fenced block is kept")
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, claude)
        XCTAssertEqual(invocation?.currentDirectory, "/projects/game", "Claude explores the project itself")
        XCTAssertEqual(invocation?.standardInput, Data(QuickCommandPrompt.body(for: request).utf8))
        XCTAssertEqual(invocation?.timeout, ClaudeQuickCommandService.timeout)
        let arguments = invocation?.arguments ?? []
        XCTAssertEqual(arguments, ClaudeQuickCommandService.arguments(projectPath: "/projects/game"))
        XCTAssertEqual(value(after: "--model", in: arguments), "sonnet")
        XCTAssertEqual(value(after: "--tools", in: arguments), "Bash,Read,Glob,Grep")
        XCTAssertEqual(value(after: "--allowedTools", in: arguments), "Bash,Read,Glob,Grep")
        XCTAssertEqual(value(after: "--setting-sources", in: arguments), "", "Lumi hooks must not fire (karar 45)")
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("--max-budget-usd"))
        XCTAssertFalse(arguments.contains("--bare"), "--bare skips the keychain → Not logged in")
    }

    func testEmptyDescriptionAndMissingCLIDoNotSpawn() async {
        let runner = FakeProcessRunner()
        let blank = QuickCommandGenerationRequest(projectPath: "/p", projectName: "P", description: "  ")
        do { _ = try await makeService(runner: runner).generate(blank); XCTFail("hata bekleniyordu") } catch {}
        do {
            _ = try await makeService(runner: runner, installed: false).generate(request)
            XCTFail("hata bekleniyordu")
        } catch let error as LumiError {
            XCTAssertEqual(error, .cliNotFound(binary: "claude"))
        } catch { XCTFail("beklenmeyen: \(error)") }
        let invocations = await runner.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testErrorEnvelopeBeatsStderrOnNonZeroExit() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(
            stdout: Self.envelope("", isError: true, subtype: "error_max_budget_usd"), stderr: "noise"
        ))
        let detail = await expectFailure(makeService(runner: runner))
        XCTAssertEqual(detail, "error_max_budget_usd")

        await runner.setDefaultResult(.failure(stderr: "Not logged in\n"))
        let stderrDetail = await expectFailure(makeService(runner: runner))
        XCTAssertEqual(stderrDetail, "Not logged in")
    }

    func testUnreadableAndEmptyRepliesFail() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success("not json"))
        let unreadable = await expectFailure(makeService(runner: runner))
        XCTAssertTrue(unreadable?.hasPrefix("unreadable reply") ?? false)

        await runner.setDefaultResult(.success(Self.envelope("```sh\n\n```")))
        let empty = await expectFailure(makeService(runner: runner))
        XCTAssertEqual(empty, "empty reply")
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
