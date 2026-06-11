import Foundation
import LumiKit

/// PTY smoke testi: forkpty + exit zincirinin çalıştığını doğrular
/// (spec/13 §5'teki node-pty check'inin native karşılığı).
/// SystemService'e composition root üzerinden enjekte edilir (design/00 §2).
public struct PTYSmokeTester: TerminalSmokeTesting {
    public init() {}

    public func runSmokeTest() async throws {
        let queue = DispatchQueue(label: "lumi.smoke.pty", qos: .utility)
        let pty = try PTYProcess(
            executable: "/bin/sh",
            args: ["-c", "exit 0"],
            cwd: "/",
            env: ["PATH": "/usr/bin:/bin"],
            initialCols: 80,
            initialRows: 24,
            queue: queue
        )

        let exitCode: Int32 = try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let once = OnceResume()
                    pty.onExit = { code in
                        once.resume { continuation.resume(returning: code) }
                    }
                    pty.startReading { _ in .proceed }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                pty.terminate()
                throw LumiError.systemCheckFailed(check: "pty", detail: "smoke test timed out")
            }
            guard let first = try await group.next() else {
                throw LumiError.systemCheckFailed(check: "pty", detail: "no exit signal")
            }
            group.cancelAll()
            return first
        }

        guard exitCode == 0 else {
            throw LumiError.systemCheckFailed(check: "pty", detail: "exit code \(exitCode)")
        }
    }
}

private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func resume(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return }
        fired = true
        body()
    }
}
