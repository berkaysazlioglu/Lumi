import Foundation
import LumiKit

/// Timeout'lu async Process koşturucu. Electron'daki execSync kullanımlarının
/// async karşılığı (karar 11: SystemChecker senkron koşmaz).
///
/// Çıktı `readabilityHandler` ile AKIŞTA toplanır: pipe buffer'ı (64KB) dolunca
/// child write'ta bloklanıp asla terminate olamazdı (klasik NSTask deadlock'u) —
/// bu, büyük çıktı veren git komutlarında sahte "timeout" üretiyordu. Stdin de
/// aynı sebepten `run()` SONRASI background'da yazılır.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

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

    /// Task iptalinde child'a continuation dışından ulaşma kutusu: `onCancel`
    /// süreç nesnesini göremez, kutu lock altında paylaşır.
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var isCancelled = false

        /// Süreci kaydeder; çağrı ZATEN iptal edilmişse `false` döner
        /// (iptal launch ile yarıştığında child ortada kalmasın).
        func attach(_ process: Process) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            self.process = process
            return !isCancelled
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let process = self.process
            lock.unlock()
            if process?.isRunning == true { process?.terminate() }
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
    /// (fixProcessPath'in 5sn timeout semantiği).
    public func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        standardInput: Data?,
        timeout: TimeInterval
    ) async -> ProcessOutput? {
        guard let raw = await runRaw(
            executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            standardInput: standardInput,
            timeout: timeout
        ) else { return nil }
        return ProcessOutput(
            exitCode: raw.exitCode,
            stdout: String(decoding: raw.stdout, as: UTF8.self),
            stderr: String(decoding: raw.stderr, as: UTF8.self)
        )
    }

    /// `run` ile aynı semantik; stdout/stderr ham `Data` olarak döner (UTF8
    /// decode kaybı olmadan — görsel blob'ları için).
    public func runRaw(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        standardInput: Data?,
        timeout: TimeInterval
    ) async -> RawProcessOutput? {
        let box = ProcessBox()
        return await withTaskCancellationHandler {
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
                let stdoutDone = OnceFlag()
                let stderrDone = OnceFlag()
                let exitDone = OnceFlag()
                let stdout = StreamCollector()
                let stderr = StreamCollector()
                // Tamamlanma = stdout EOF + stderr EOF + termination (üçü birden):
                // yalnız termination'ı beklemek son chunk'ları yarıştırırdı.
                // Her `enter` TEK bir kapıdan `leave` edilir — timeout ve
                // launch-failure yolları da aynı kapıları kullanır. Dengesiz
                // grupta `notify` hiç koşmaz ve process + collector sızardı.
                let group = DispatchGroup()
                group.enter()
                group.enter()
                group.enter()

                @Sendable func finishStdout() {
                    guard stdoutDone.tryFire() else { return }
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    group.leave()
                }
                @Sendable func finishStderr() {
                    guard stderrDone.tryFire() else { return }
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    group.leave()
                }
                @Sendable func finishExit() {
                    guard exitDone.tryFire() else { return }
                    group.leave()
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        finishStdout()
                    } else {
                        stdout.append(chunk)
                    }
                }
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        finishStderr()
                    } else {
                        stderr.append(chunk)
                    }
                }
                process.terminationHandler = { _ in
                    finishExit()
                }
                group.notify(queue: .global(qos: .utility)) {
                    // `once` yanmışsa (timeout/launch failure) sonuç zaten
                    // verildi; `terminationStatus` okunmaz.
                    guard once.tryFire() else { return }
                    continuation.resume(returning: RawProcessOutput(
                        exitCode: process.terminationStatus,
                        stdout: stdout.bytes,
                        stderr: stderr.bytes
                    ))
                }

                do {
                    try process.run()
                } catch {
                    if once.tryFire() {
                        continuation.resume(returning: nil)
                    }
                    // Grup dengelenir: notify koşar, `once` yandığı için hiçbir
                    // şey yapmadan çıkar ve tuttuğu referansları bırakır.
                    finishStdout()
                    finishStderr()
                    finishExit()
                    return
                }

                // Launch ile iptal yarıştıysa child'ı hemen sonlandır.
                if !box.attach(process) { process.terminate() }

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
                    continuation.resume(returning: nil)
                    // Handler'lar kapatılır ve grup dengelenir; kalan
                    // `finishExit` terminationHandler'dan gelir.
                    finishStdout()
                    finishStderr()
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}
