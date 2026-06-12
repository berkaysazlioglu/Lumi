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
}
