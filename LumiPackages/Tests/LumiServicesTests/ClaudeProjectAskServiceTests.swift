import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

/// Karar 103 Faz 5: salt-okunur proje sorusu ajanı.
final class ClaudeProjectAskServiceTests: XCTestCase {
    private let claude = "/Users/me/.local/bin/claude"

    private func makeService(runner: FakeProcessRunner, installed: Bool = true) -> ClaudeProjectAskService {
        ClaudeProjectAskService(runner: runner, locator: FakeBinaryLocator(paths: installed ? ["claude": claude] : [:]))
    }

    private static func envelope(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func testRunsReadOnlyClaudeInProjectRootWithProjectSettings() async throws {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(Self.envelope([
            "type": "result", "is_error": false, "result": "  Bir Unity oyunu. Giriş: Assets/Main.cs\n",
            "total_cost_usd": 0.12, "duration_ms": 34_000,
        ])))
        let service = makeService(runner: runner)

        let answer = try await service.ask(projectPath: "/p/game", question: " projeyi özetle ")

        XCTAssertEqual(answer, ProjectAnswer(text: "Bir Unity oyunu. Giriş: Assets/Main.cs", costUSD: 0.12, durationSeconds: 34))
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, claude)
        XCTAssertEqual(invocation?.currentDirectory, "/p/game")
        XCTAssertEqual(invocation?.standardInput, Data("projeyi özetle".utf8))
        XCTAssertEqual(invocation?.timeout, ClaudeProjectAskService.timeout)
        let args = invocation?.arguments ?? []
        XCTAssertEqual(value(after: "--tools", in: args), "Read,Glob,Grep", "Bash ve yazma araçları yok")
        XCTAssertEqual(value(after: "--allowedTools", in: args), "Read,Glob,Grep")
        XCTAssertEqual(value(after: "--setting-sources", in: args), "project", "proje CLAUDE.md'si yüklenir, kullanıcı hook'ları yüklenmez")
        XCTAssertEqual(value(after: "--max-budget-usd", in: args), ClaudeProjectAskService.maxBudgetUSD)
        XCTAssertTrue(args.contains("--no-session-persistence"))
        XCTAssertTrue(args.contains("--strict-mcp-config"), "kullanıcı MCP şemaları ~100 bin token ekliyordu")
    }

    func testErrorEnvelopeAndFailuresSurfaceAsProjectQuestionErrors() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 1, stdout: Self.envelope([
            "type": "result", "is_error": true, "subtype": "error_max_budget_usd", "result": "",
        ])))
        let service = makeService(runner: runner)
        await assertThrows(.projectQuestionFailed(detail: "error_max_budget_usd")) {
            _ = try await service.ask(projectPath: "/p", question: "q")
        }

        await runner.setDefaultResult(.failure(exitCode: 1, stderr: "Not logged in"))
        await assertThrows(.projectQuestionFailed(detail: "Not logged in")) {
            _ = try await service.ask(projectPath: "/p", question: "q")
        }
    }

    func testMissingCLIOrEmptyQuestionNeverSpawns() async {
        let runner = FakeProcessRunner()
        await assertThrows(.cliNotFound(binary: "claude")) {
            _ = try await self.makeService(runner: runner, installed: false).ask(projectPath: "/p", question: "q")
        }
        await assertThrows(.projectQuestionFailed(detail: "empty question")) {
            _ = try await self.makeService(runner: runner).ask(projectPath: "/p", question: "  ")
        }
        let invocations = await runner.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    private func assertThrows(_ expected: LumiError, _ body: () async throws -> Void, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("hata bekleniyordu", line: line)
        } catch let error as LumiError {
            XCTAssertEqual(error, expected, line: line)
        } catch {
            XCTFail("beklenmeyen: \(error)", line: line)
        }
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
