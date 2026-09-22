import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

final class QuickCommandBackgroundLauncherTests: XCTestCase {
    func testPassesPathsAsPositionalArgumentsToADetachingShell() async throws {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.success())
        try await QuickCommandBackgroundLauncher(runner: runner)
            .launch(scriptPath: "/s/a b.sh", workingDirectory: "/w/it's", logPath: "/s/a b.log")
        let invocation = await runner.invocations.first
        XCTAssertEqual(invocation?.executable, "/bin/sh")
        XCTAssertEqual(invocation?.arguments, [
            "-c", QuickCommandBackgroundLauncher.launcherScript, "lumi-start-app", "/w/it's", "/s/a b.sh", "/s/a b.log",
        ], "paths never get interpolated into the shell string")
        XCTAssertTrue(QuickCommandBackgroundLauncher.launcherScript.contains("nohup"))
        XCTAssertTrue(QuickCommandBackgroundLauncher.launcherScript.hasSuffix("&"))
    }

    func testLaunchFailureThrowsSpawnFailed() async {
        let runner = FakeProcessRunner()
        await runner.setDefaultResult(.failure(exitCode: 2, stderr: "cd: no such directory\n"))
        do {
            try await QuickCommandBackgroundLauncher(runner: runner)
                .launch(scriptPath: "/s", workingDirectory: "/missing", logPath: "/l")
            XCTFail("hata bekleniyordu")
        } catch let error as LumiError {
            XCTAssertEqual(error, .spawnFailed(reason: "cd: no such directory"))
        } catch { XCTFail("beklenmeyen: \(error)") }
    }

    /// Gerçek `/bin/sh`: başlatıcı script'in bitmesini beklemeden döner ve
    /// script çalışma dizininde koşup çıktısını log'a yazar.
    func testRealLaunchReturnsBeforeTheScriptFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumi-bg-\(UUID().uuidString)")
        let work = root.appendingPathComponent("work dir")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("start.sh")
        let log = root.appendingPathComponent("start.log")
        try "sleep 1\npwd\necho done\n".write(to: script, atomically: true, encoding: .utf8)

        let started = Date()
        try await QuickCommandBackgroundLauncher()
            .launch(scriptPath: script.path, workingDirectory: work.path, logPath: log.path)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.9, "launcher must not wait for the script")

        for _ in 0 ..< 50 {
            if let text = try? String(contentsOf: log, encoding: .utf8), text.contains("done") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        for _ in 0 ..< 50 {
            if let text = try? String(contentsOf: log, encoding: .utf8), text.contains("[lumi]") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let output = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(output.contains("work dir"), "runs in the checkout: \(output)")
        XCTAssertTrue(output.contains("done"))
        XCTAssertTrue(output.hasSuffix("[lumi] exited with status 0\n"), output)
    }

    /// Sessizce kapanan script (stdin isteyen CLI gibi) log'da teşhis edilebilir.
    func testRealLaunchRecordsFailingExitStatusAndHasNoStdin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lumi-bg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("start.sh")
        let log = root.appendingPathComponent("start.log")
        try "read answer || echo no-input\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)

        try await QuickCommandBackgroundLauncher()
            .launch(scriptPath: script.path, workingDirectory: root.path, logPath: log.path)
        for _ in 0 ..< 50 {
            if let text = try? String(contentsOf: log, encoding: .utf8), text.contains("[lumi]") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let output = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(output.contains("no-input"), "stdin is /dev/null: \(output)")
        XCTAssertTrue(output.hasSuffix("[lumi] exited with status 3\n"), output)
    }
}
