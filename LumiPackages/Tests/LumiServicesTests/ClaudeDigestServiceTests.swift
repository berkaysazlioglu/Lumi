import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

/// Karar 104 Faz 4: uzun ajan mesajının haiku özeti.
final class ClaudeDigestServiceTests: XCTestCase {
    private let claude = "/Users/me/.local/bin/claude"

    private func makeService(runner: FakeProcessRunner, installed: Bool = true) -> ClaudeDigestService {
        ClaudeDigestService(
            runner: runner,
            locator: FakeBinaryLocator(paths: installed ? ["claude": claude] : [:]),
            workingDirectory: "/tmp/lumi-scratch"
        )
    }

    private static func envelope(_ result: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "result": result])
        return String(decoding: data, as: UTF8.self)
    }

    func testRunsToollessHaikuWithMessageOnStdinAndParsesJSON() async throws {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(Self.envelope(#"```json\n{"summary":"Testleri düzeltti. Commit sorusu var.","needsUser":true}\n```"#)))
        let service = makeService(runner: runner)

        let digest = try await service.summarize(agentMessage: "uzun mesaj", terminalTitle: "api-refactor")

        XCTAssertEqual(digest, TerminalDigest(summary: "Testleri düzeltti. Commit sorusu var.", needsUser: true))
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, claude)
        XCTAssertEqual(invocation?.arguments, ClaudeDigestService.arguments)
        XCTAssertEqual(invocation?.arguments.contains("haiku"), true)
        XCTAssertEqual(invocation?.currentDirectory, "/tmp/lumi-scratch")
        let stdin = String(decoding: invocation?.standardInput ?? Data(), as: UTF8.self)
        XCTAssertTrue(stdin.contains("Terminal: api-refactor"))
        XCTAssertTrue(stdin.hasSuffix("uzun mesaj"))
    }

    func testSessionSummaryUsesItsOwnInstructionAndSendsTheTranscript() async throws {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(Self.envelope(#"{"summary":"Login akışını yazıyor.","needsUser":false}"#)))
        let service = makeService(runner: runner)

        let digest = try await service.summarizeSession(transcript: "[user] login yaz", terminalTitle: "api")

        XCTAssertEqual(digest.summary, "Login akışını yazıyor.")
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.arguments, ClaudeDigestService.sessionArguments)
        XCTAssertNotEqual(ClaudeDigestService.sessionArguments, ClaudeDigestService.arguments)
        XCTAssertEqual(invocation?.arguments.contains("--strict-mcp-config"), true)
        let stdin = String(decoding: invocation?.standardInput ?? Data(), as: UTF8.self)
        XCTAssertTrue(stdin.hasSuffix("[user] login yaz"))
    }

    func testUnreadableReplyAndFailuresThrow() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success(Self.envelope("Sorry, I can't.")))
        let service = makeService(runner: runner)
        do {
            _ = try await service.summarize(agentMessage: "x", terminalTitle: "t")
            XCTFail("hata bekleniyordu")
        } catch {}

        await runner.setDefaultResult(.failure(exitCode: 1, stderr: "Not logged in"))
        do {
            _ = try await service.summarize(agentMessage: "x", terminalTitle: "t")
            XCTFail("hata bekleniyordu")
        } catch let error as LumiError {
            XCTAssertEqual(error, .digestFailed(detail: "Not logged in"))
        } catch { XCTFail("beklenmeyen: \(error)") }
    }

    func testParseDefaultsNeedsUserToFalseAndRejectsEmptySummary() {
        XCTAssertEqual(ClaudeDigestService.parse(#"{"summary":"ok"}"#), TerminalDigest(summary: "ok", needsUser: false))
        XCTAssertNil(ClaudeDigestService.parse(#"{"summary":"  "}"#))
        XCTAssertNil(ClaudeDigestService.parse("no json"))
    }
}
