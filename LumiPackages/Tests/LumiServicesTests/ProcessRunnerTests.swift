import XCTest
@testable import LumiServices

/// ProcessRunner: pipe-deadlock regresyonları. Çıktı/girdi 64KB pipe buffer'ını
/// aştığında eski implementasyon (terminationHandler içinde readDataToEndOfFile,
/// run() öncesi senkron stdin yazımı) süresiz bloklanıp sahte timeout üretiyordu.
final class ProcessRunnerTests: XCTestCase {
    func testBasicCommandCapturesStdoutAndExitCode() async {
        let output = await ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "printf hello; exit 3"],
            timeout: 5
        )

        XCTAssertEqual(output?.stdout, "hello")
        XCTAssertEqual(output?.exitCode, 3)
    }

    func testCapturesStderrSeparately() async {
        let output = await ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "printf out; printf err 1>&2"],
            timeout: 5
        )

        XCTAssertEqual(output?.stdout, "out")
        XCTAssertEqual(output?.stderr, "err")
    }

    func testLargeOutputDoesNotDeadlock() async {
        // 512KB stdout — 64KB pipe buffer'ının 8 katı; akışta okunmazsa child
        // write'ta bloklanır ve test timeout'a düşerdi.
        let output = await ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "dd if=/dev/zero bs=1024 count=512 2>/dev/null | tr '\\0' 'x'"],
            timeout: 10
        )

        XCTAssertEqual(output?.exitCode, 0)
        XCTAssertEqual(output?.stdout.count, 512 * 1024)
    }

    func testLargeStdinRoundTripsThroughCat() async {
        // 256KB stdin → cat → stdout: run() öncesi senkron stdin yazımı burada
        // çağıran thread'i süresiz bloklardı.
        let payload = Data(repeating: UInt8(ascii: "y"), count: 256 * 1024)
        let output = await ProcessRunner.run(
            "/bin/cat",
            arguments: [],
            standardInput: payload,
            timeout: 10
        )

        XCTAssertEqual(output?.exitCode, 0)
        XCTAssertEqual(output?.stdout.count, payload.count)
    }

    func testTimeoutReturnsNil() async {
        let start = Date()
        let output = await ProcessRunner.run(
            "/bin/sleep",
            arguments: ["30"],
            timeout: 0.5
        )

        XCTAssertNil(output)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testLaunchFailureReturnsNil() async {
        let output = await ProcessRunner.run(
            "/yok/boyle/bir/binary",
            arguments: [],
            timeout: 5
        )

        XCTAssertNil(output)
    }

    // MARK: - Sızıntı ve iptal (1.11)

    /// Timeout yolunda DispatchGroup dengesizdi (`enter` var, `leave` yok) →
    /// `notify` hiç koşmuyor, process + pipe'lar sonsuza dek tutuluyordu.
    /// Sızıntı açık kalan pipe fd'leriyle ölçülür.
    func testTimeoutDoesNotLeakPipeFileDescriptors() async throws {
        // Isınma: ilk koşu tembel global'leri kurar, fd sayımını kaydırmasın.
        _ = await ProcessRunner.run("/bin/sleep", arguments: ["30"], timeout: 0.3)
        try await Task.sleep(for: .milliseconds(200))

        let before = Self.openFileDescriptorCount()
        for _ in 0 ..< 8 {
            _ = await ProcessRunner.run("/bin/sleep", arguments: ["30"], timeout: 0.3)
        }
        try await Task.sleep(for: .milliseconds(300))
        let after = Self.openFileDescriptorCount()

        XCTAssertLessThan(
            after - before, 8,
            "timeout yolunda pipe fd'leri sızıyor: \(before) → \(after)"
        )
    }

    /// Task iptali child süreci öldürmeliydi; eski implementasyonda çağrı
    /// timeout'a kadar (burada 30 sn) askıda kalıyordu.
    func testCancellationTerminatesChildProcess() async throws {
        let pidFile = Self.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: pidFile) }

        let task = Task {
            await ProcessRunner.run(
                "/bin/sh",
                arguments: ["-c", "echo $$ > \(pidFile); exec sleep 30"],
                timeout: 30
            )
        }
        let pid = try await Self.waitForPid(in: pidFile)

        task.cancel()
        let start = Date()
        _ = await task.value
        XCTAssertLessThan(
            Date().timeIntervalSince(start), 5,
            "iptalden sonra çağrı hemen dönmeliydi"
        )
        let exited = await Self.waitForExit(pid)
        XCTAssertTrue(exited, "iptal child süreci öldürmedi (pid \(pid))")
    }

    func testTimeoutTerminatesChildProcess() async throws {
        let pidFile = Self.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: pidFile) }

        let output = await ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "echo $$ > \(pidFile); exec sleep 30"],
            timeout: 0.5
        )

        XCTAssertNil(output)
        let pid = try await Self.waitForPid(in: pidFile)
        let exited = await Self.waitForExit(pid)
        XCTAssertTrue(exited, "timeout child süreci öldürmedi (pid \(pid))")
    }

    // MARK: - Yardımcılar

    private static func temporaryPath() -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("lumi-pid-\(UUID().uuidString)")
    }

    private static func openFileDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }

    private static func waitForPid(in path: String, timeout: TimeInterval = 5) async throws -> pid_t {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let raw = try? String(contentsOfFile: path, encoding: .utf8),
               let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw LumiTestFailure.pidNotWritten
    }

    private static func waitForExit(_ pid: pid_t, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private enum LumiTestFailure: Error {
        case pidNotWritten
    }
}
