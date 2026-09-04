import Foundation
import XCTest
@testable import LumiServices

/// CodexAppServerProbe iptal / timeout / launch davranışı.
///
/// Gerçek `codex` yerine argümanlarını yok sayan, stdio'yu açık tutan ama HİÇ
/// yanıt vermeyen bir kabuk betiği kullanılır: probe'un yoklama döngüsü tam da
/// bu durumda 30 sn dönüyordu (1.7).
final class CodexAppServerProbeTests: XCTestCase {
    private var scriptURL: URL!
    private var pidFile: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        scriptURL = base.appendingPathComponent("fake-app-server.sh")
        pidFile = base.appendingPathComponent("pid")
        try """
        #!/bin/sh
        echo $$ > \(pidFile.path)
        exec sleep 30
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    func testCancellationStopsProbeAndKillsChild() async throws {
        let script = scriptURL.path
        let task = Task {
            try await CodexAppServerProbe.requestResponseLine(
                binary: script, method: "account/rateLimits/read", timeout: 30
            )
        }
        let pid = try await waitForPid()

        task.cancel()
        let start = Date()
        do {
            _ = try await task.value
            XCTFail("iptal edilen probe sonuç döndürdü")
        } catch is CancellationError {
            // beklenen
        } catch {
            XCTFail("beklenmeyen hata: \(error)")
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(start), 5,
            "iptalden sonra probe hemen dönmeliydi (30 sn busy-loop regresyonu)"
        )
        let exited = await waitForExit(pid)
        XCTAssertTrue(exited, "iptalde app-server süreci öldürülmedi (pid \(pid))")
    }

    func testTimeoutStopsProbeAndKillsChild() async throws {
        let start = Date()
        do {
            _ = try await CodexAppServerProbe.requestResponseLine(
                binary: scriptURL.path, method: "account/rateLimits/read", timeout: 0.5
            )
            XCTFail("yanıt vermeyen süreçte probe başarılı oldu")
        } catch CodexAppServerProbe.ProbeError.timedOut {
            // beklenen
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)

        let pid = try await waitForPid()
        let exited = await waitForExit(pid)
        XCTAssertTrue(exited, "timeout'ta app-server süreci öldürülmedi (pid \(pid))")
    }

    /// `shutdown()` başlatılamamış süreçte `waitUntilExit()` çağırmamalı.
    func testLaunchFailureReportsLaunchFailed() async throws {
        do {
            _ = try await CodexAppServerProbe.requestResponseLine(
                binary: "/yok/boyle/bir/binary", method: "m", timeout: 1
            )
            XCTFail("olmayan binary ile probe başarılı oldu")
        } catch CodexAppServerProbe.ProbeError.launchFailed {
            // beklenen
        }
    }

    // MARK: - Yardımcılar

    private func waitForPid(timeout: TimeInterval = 5) async throws -> pid_t {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let raw = try? String(contentsOf: pidFile, encoding: .utf8),
               let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ProbeTestFailure.pidNotWritten
    }

    private func waitForExit(_ pid: pid_t, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private enum ProbeTestFailure: Error {
        case pidNotWritten
    }
}
