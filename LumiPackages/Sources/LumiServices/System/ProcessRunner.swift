import Foundation

/// Timeout'lu async Process koşturucu. Electron'daki execSync kullanımlarının
/// async karşılığı (karar 11: SystemChecker senkron koşmaz).
///
/// Çıktı `readabilityHandler` ile AKIŞTA toplanır: pipe buffer'ı (64KB) dolunca
/// child write'ta bloklanıp asla terminate olamazdı (klasik NSTask deadlock'u) —
/// bu, büyük çıktı veren git komutlarında sahte "timeout" üretiyordu. Stdin de
/// aynı sebepten `run()` SONRASI background'da yazılır.
enum ProcessRunner {
    struct Output: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Binary-güvenli varyantın çıktısı: stdout UTF8'e çevrilmeden döner
    /// (görsel blob'ları — `git show sha:file`, karar 21).
    struct RawOutput: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
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

    /// readabilityHandler'lar arbitrer thread'lerden yazar — lock'lu biriktirici.
    private final class StreamCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk)
        }

        var bytes: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
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
        guard let raw = await runRaw(
            executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            standardInput: standardInput,
            timeout: timeout
        ) else { return nil }
        return Output(
            exitCode: raw.exitCode,
            stdout: String(decoding: raw.stdout, as: UTF8.self),
            stderr: String(decoding: raw.stderr, as: UTF8.self)
        )
    }

    /// `run` ile aynı semantik; stdout/stderr ham `Data` olarak döner (UTF8
    /// decode kaybı olmadan — görsel blob'ları için).
    static func runRaw(
        _ executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        standardInput: Data? = nil,
        timeout: TimeInterval
    ) async -> RawOutput? {
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
            let stdinPipe: Pipe? = standardInput.map { _ in Pipe() }
            if let stdinPipe {
                process.standardInput = stdinPipe
            }

            let once = OnceFlag()
            let stdout = StreamCollector()
            let stderr = StreamCollector()
            // Tamamlanma = stdout EOF + stderr EOF + termination (üçü birden):
            // yalnız termination'ı beklemek son chunk'ları yarıştırırdı.
            let group = DispatchGroup()

            group.enter()
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                } else {
                    stdout.append(chunk)
                }
            }
            group.enter()
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                } else {
                    stderr.append(chunk)
                }
            }
            group.enter()
            process.terminationHandler = { _ in
                group.leave()
            }
            group.notify(queue: .global(qos: .utility)) {
                guard once.tryFire() else { return }
                continuation.resume(returning: RawOutput(
                    exitCode: process.terminationStatus,
                    stdout: stdout.bytes,
                    stderr: stderr.bytes
                ))
            }

            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if once.tryFire() {
                    continuation.resume(returning: nil)
                }
                return
            }

            if let stdinPipe, let standardInput {
                // run() sonrası, background'da: 64KB üstü input'ta senkron write
                // çağıran thread'i süresiz bloklardı (child henüz okumuyorken).
                DispatchQueue.global(qos: .utility).async {
                    stdinPipe.fileHandleForWriting.write(standardInput)
                    stdinPipe.fileHandleForWriting.closeFile()
                }
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning, once.tryFire() else { return }
                process.terminate()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
