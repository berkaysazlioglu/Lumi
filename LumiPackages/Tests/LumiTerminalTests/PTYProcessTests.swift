import Darwin
import XCTest
@testable import LumiTerminal

/// PTY katmanı entegrasyon testleri (design/04 P3 kapsamının otomatize kısmı).
final class PTYProcessTests: XCTestCase {
    private let env = ["TERM": "xterm-256color", "PATH": "/usr/bin:/bin"]

    private func makeQueue() -> DispatchQueue {
        DispatchQueue(label: "lumi.test.pty.\(UUID().uuidString)", qos: .utility)
    }

    private func spawn(
        _ executable: String,
        args: [String] = [],
        queue: DispatchQueue
    ) throws -> PTYProcess {
        try PTYProcess(
            executable: executable,
            args: args,
            cwd: "/tmp",
            env: env,
            initialCols: 80,
            initialRows: 24,
            queue: queue
        )
    }

    func testEchoRoundTripThroughCat() throws {
        let queue = makeQueue()
        let pty = try spawn("/bin/cat", queue: queue)
        let gotEcho = expectation(description: "cat echoes input")
        gotEcho.assertForOverFulfill = false

        let collected = OutputCollector()
        pty.startReading { data in
            if collected.appendAndCheck(data, contains: "hello-pty") {
                gotEcho.fulfill()
            }
            return .proceed
        }
        queue.async {
            pty.write(Data("hello-pty\n".utf8))
        }

        wait(for: [gotEcho], timeout: 5)
        pty.terminate()
    }

    func testCleanExitDeliversCodeZero() throws {
        let queue = makeQueue()
        let pty = try spawn("/bin/sh", args: ["-c", "echo done"], queue: queue)
        let exited = expectation(description: "exit callback")

        nonisolated(unsafe) var exitCode: Int32 = -99
        pty.onExit = { code in
            exitCode = code
            exited.fulfill()
        }
        pty.startReading { _ in .proceed }

        wait(for: [exited], timeout: 5)
        XCTAssertEqual(exitCode, 0)
    }

    func testTerminateDeliversSignalExitCode() throws {
        let queue = makeQueue()
        let pty = try spawn("/bin/cat", queue: queue)
        let exited = expectation(description: "exit callback")

        nonisolated(unsafe) var exitCode: Int32 = -99
        pty.onExit = { code in
            exitCode = code
            exited.fulfill()
        }
        pty.startReading { _ in .proceed }
        pty.terminate()

        wait(for: [exited], timeout: 5)
        XCTAssertEqual(exitCode, 128 + SIGHUP)
    }

    func testTerminateKillsProcessGroup() throws {
        let queue = makeQueue()
        let pty = try spawn("/bin/zsh", args: ["-c", "sleep 300"], queue: queue)
        let exited = expectation(description: "exit callback")
        pty.onExit = { _ in exited.fulfill() }
        pty.startReading { _ in .proceed }

        // Session leader hayatta mı?
        XCTAssertEqual(kill(pty.pid, 0), 0)

        pty.terminate()
        wait(for: [exited], timeout: 5)

        // Process group'ta canlı üye kalmamalı (zombi claude ağacı garantisi)
        let deadline = Date().addingTimeInterval(2)
        while killpg(pty.pid, 0) == 0 && Date() < deadline {
            usleep(50_000)
        }
        XCTAssertEqual(killpg(pty.pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testSuspendStopsDeliveryUntilResume() throws {
        let queue = makeQueue()
        // Kendi başına 300KB üreten süreç: suspend'de kernel PTY buffer'ı dolar
        // ve yazan süreç doğal bloklanır (spec/00 §4.1-2'nin birebir kanıtı).
        let pty = try spawn("/bin/sh", args: ["-c", "yes | head -c 300000"], queue: queue)

        let firstChunk = expectation(description: "first chunk")
        firstChunk.assertForOverFulfill = false
        let counter = ChunkCounter()

        pty.startReading { data in
            let count = counter.record(data.count)
            if count == 1 {
                firstChunk.fulfill()
                return .suspend
            }
            return .proceed
        }

        wait(for: [firstChunk], timeout: 5)
        let countAfterSuspend = counter.callCount

        // Suspend'deyken yeni teslimat olmamalı; yazan süreç bloklanmış beklemede
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(counter.callCount, countAfterSuspend, "suspend'de chunk teslim edildi")

        // Resume sonrası kalan veri akmalı (tty ONLCR ile çıktı 300KB'den büyük olabilir)
        pty.resumeReading()
        let deadline = Date().addingTimeInterval(5)
        while counter.totalBytes < 100 * 1024 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertGreaterThan(counter.totalBytes, 100 * 1024, "resume sonrası veri akmadı")

        pty.terminate()
    }

    func testWriteAfterExitIsSafe() throws {
        let queue = makeQueue()
        let pty = try spawn("/bin/sh", args: ["-c", "true"], queue: queue)
        let exited = expectation(description: "exit")
        pty.onExit = { _ in exited.fulfill() }
        pty.startReading { _ in .proceed }
        wait(for: [exited], timeout: 5)

        // Çökmemeli, sessizce yutulmalı (yaşam döngüsü guard'ı)
        queue.sync {
            pty.write(Data("late\n".utf8))
        }
    }
}

/// Test handler'ı io queue'da koşar; biriktirici thread-safe olmalı.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func appendAndCheck(_ data: Data, contains needle: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        return String(decoding: buffer, as: UTF8.self).contains(needle)
    }
}

/// Test handler'ı io queue'da koşar; sayaç thread-safe olmalı.
private final class ChunkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var bytes = 0

    func record(_ byteCount: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        bytes += byteCount
        return count
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    var totalBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }
}
