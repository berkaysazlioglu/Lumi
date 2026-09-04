import Foundation
import LumiKit
import LumiTestSupport
import XCTest

@testable import LumiServices

final class ClaudeOAuthCredentialsTests: XCTestCase {
    func testExtractsAccessTokenFromCredentialsJSON() {
        let raw = #"{"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"r","expiresAt":1}}"#

        XCTAssertEqual(ClaudeOAuthCredentials.accessToken(fromJSON: raw), "tok-123")
    }

    func testIgnoresExpiryBecauseServerIsAuthoritative() {
        // Süresi geçmiş görünen token da döner: 401'i sunucu verir (Orca gerekçesi).
        let raw = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":0}}"#

        XCTAssertEqual(ClaudeOAuthCredentials.accessToken(fromJSON: raw), "tok")
    }

    func testReturnsNilWhenTokenMissingEmptyOrMalformed() {
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(fromJSON: #"{"claudeAiOauth":{}}"#))
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(
            fromJSON: #"{"claudeAiOauth":{"accessToken":"   "}}"#
        ))
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(fromJSON: #"{"other":1}"#))
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(fromJSON: "not json"))
    }

    // MARK: - Kaynak sırası (refactor 3.1: enjekte edilen ProcessRunning)

    private static let keychainCommand =
        "/usr/bin/security find-generic-password -s Claude Code-credentials -a ada -w"

    private func credentials(
        runner: FakeProcessRunner,
        fileJSON: String? = nil
    ) -> ClaudeOAuthCredentials {
        ClaudeOAuthCredentials(
            runner: runner,
            readFile: { _ in fileJSON.map { Data($0.utf8) } }
        )
    }

    func testPrefersKeychainOverCredentialsFile() async {
        let runner = FakeProcessRunner()
        await runner.stub(
            commandLine: Self.keychainCommand,
            with: .success(#"{"claudeAiOauth":{"accessToken":"keychain-tok"}}"#)
        )
        let subject = credentials(
            runner: runner,
            fileJSON: #"{"claudeAiOauth":{"accessToken":"file-tok"}}"#
        )

        let token = await subject.readAccessToken(homeDirectory: "/home/ada", user: "ada")

        XCTAssertEqual(token, "keychain-tok")
    }

    func testFallsBackToCredentialsFileWhenKeychainFails() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 44))
        let subject = credentials(
            runner: runner,
            fileJSON: #"{"claudeAiOauth":{"accessToken":"file-tok"}}"#
        )

        let token = await subject.readAccessToken(homeDirectory: "/home/ada", user: "ada")

        XCTAssertEqual(token, "file-tok")
    }

    func testKeychainTimeoutStillFallsBackToFile() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.timeout)
        let subject = credentials(
            runner: runner,
            fileJSON: #"{"claudeAiOauth":{"accessToken":"file-tok"}}"#
        )

        let token = await subject.readAccessToken(homeDirectory: "/home/ada", user: "ada")

        XCTAssertEqual(token, "file-tok")
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.timeout, ClaudeOAuthCredentials.keychainTimeout)
    }

    func testReturnsNilWhenNeitherSourceHasAToken() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 44))

        let token = await credentials(runner: runner)
            .readAccessToken(homeDirectory: "/home/ada", user: "ada")

        XCTAssertNil(token)
    }

    func testKeychainQueryUsesClaudeCodeServiceAndCurrentUser() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 44))

        _ = await credentials(runner: runner)
            .readAccessToken(homeDirectory: "/home/ada", user: "ada")

        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, "/usr/bin/security")
        XCTAssertEqual(invocation?.arguments, [
            "find-generic-password", "-s", "Claude Code-credentials", "-a", "ada", "-w",
        ])
    }
}
