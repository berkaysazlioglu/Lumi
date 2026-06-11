import Foundation

/// Timeout'lu async Process koşturucu. Electron'daki execSync kullanımlarının
/// async karşılığı (karar 11: SystemChecker senkron koşmaz).
enum ProcessRunner {
    struct Output: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func tryFire() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    /// Timeout veya başlatma hatasında nil döner; sessiz-fail sözleşmesi
    /// (fixProcessPath'in 5sn timeout semantiği, spec/13).
    static func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        standardInput: Data? = nil,
        timeout: TimeInterval
    ) async -> Output? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            if let standardInput {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                stdinPipe.fileHandleForWriting.write(standardInput)
                stdinPipe.fileHandleForWriting.closeFile()
            }

            let once = OnceFlag()
            process.terminationHandler = { finished in
                guard once.tryFire() else { return }
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Output(
                    exitCode: finished.terminationStatus,
                    stdout: String(decoding: data, as: UTF8.self),
                    stderr: String(decoding: errorData, as: UTF8.self)
                ))
            }

            do {
                try process.run()
            } catch {
                if once.tryFire() {
                    continuation.resume(returning: nil)
                }
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning, once.tryFire() else { return }
                process.terminate()
                continuation.resume(returning: nil)
            }
        }
    }
}
