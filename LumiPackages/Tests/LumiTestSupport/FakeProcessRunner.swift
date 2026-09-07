import Foundation
import LumiKit

/// `ProcessRunning` test ikamesi (refactor 3.1). Komut → sonuç eşlemesi,
/// çağrı kaydı ve gecikme/timeout simülasyonu sağlar; gerçek bir binary
/// gerekmeden servis birim testi yazılabilir.
///
/// Eşleme sırası: (1) tam `executable + arguments` anahtarı,
/// (2) yalnız `executable` anahtarı, (3) `defaultResult`.
public actor FakeProcessRunner: ProcessRunning {
    /// Tek bir çağrının kaydı.
    public struct Invocation: Sendable, Equatable {
        public let executable: String
        public let arguments: [String]
        public let currentDirectory: String?
        public let standardInput: Data?
        public let timeout: TimeInterval
        public let isRaw: Bool

        /// `/usr/bin/git status --porcelain` biçiminde okunabilir komut satırı.
        public var commandLine: String {
            ([executable] + arguments).joined(separator: " ")
        }
    }

    /// Bir komutun simüle edilmiş sonucu. `nil` sonuç = timeout/launch failure
    /// (`ProcessRunning`in sessiz-fail sözleşmesi).
    public struct Result: Sendable {
        public var exitCode: Int32
        public var stdout: Data
        public var stderr: Data
        /// Sonuç dönmeden önce beklenecek süre (eşzamanlılık testleri için).
        public var delay: Duration
        /// true ise çağrı `nil` döner — timeout/başlatma hatası simülasyonu.
        public var isTimeout: Bool

        public init(
            exitCode: Int32 = 0,
            stdout: Data = Data(),
            stderr: Data = Data(),
            delay: Duration = .zero,
            isTimeout: Bool = false
        ) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
            self.delay = delay
            self.isTimeout = isTimeout
        }

        public static func success(
            _ stdout: String = "",
            stderr: String = "",
            delay: Duration = .zero
        ) -> Result {
            Result(
                exitCode: 0,
                stdout: Data(stdout.utf8),
                stderr: Data(stderr.utf8),
                delay: delay
            )
        }

        public static func failure(
            exitCode: Int32 = 1,
            stdout: String = "",
            stderr: String = ""
        ) -> Result {
            Result(exitCode: exitCode, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
        }

        public static func binary(_ stdout: Data, exitCode: Int32 = 0) -> Result {
            Result(exitCode: exitCode, stdout: stdout)
        }

        /// Timeout / başlatılamama: çağıran `nil` görür.
        public static let timeout = Result(isTimeout: true)
    }

    // MARK: Ayarlanabilir davranış

    /// Hiçbir eşleşme yoksa dönen sonuç. Default: exit 0, boş çıktı.
    public var defaultResult: Result = .success()

    private var byCommandLine: [String: Result] = [:]
    private var byExecutable: [String: Result] = [:]

    // MARK: Çağrı kaydı

    public private(set) var invocations: [Invocation] = []
    /// Aynı anda uçuşta olan çağrı sayısının tepe değeri (eşzamanlılık testleri).
    public private(set) var maxConcurrentInvocations = 0
    private var inFlight = 0

    public init() {}

    /// Tam komut satırı eşlemesi: `"/usr/bin/git status --porcelain"`.
    public func stub(commandLine: String, with result: Result) {
        byCommandLine[commandLine] = result
    }

    /// Argümandan bağımsız executable eşlemesi: `"/usr/bin/which"`.
    public func stub(executable: String, with result: Result) {
        byExecutable[executable] = result
    }

    public func setDefaultResult(_ result: Result) {
        defaultResult = result
    }

    public func reset() {
        invocations = []
        maxConcurrentInvocations = 0
        byCommandLine = [:]
        byExecutable = [:]
        defaultResult = .success()
    }

    // MARK: Sorgular

    public var commandLines: [String] { invocations.map(\.commandLine) }

    public func invocationCount(executable: String) -> Int {
        invocations.filter { $0.executable == executable }.count
    }

    public func didRun(commandLine: String) -> Bool {
        commandLines.contains(commandLine)
    }

    // MARK: - ProcessRunning

    public func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        standardInput: Data?,
        timeout: TimeInterval
    ) async -> ProcessOutput? {
        guard let raw = await record(
            executable, arguments, currentDirectory, standardInput, timeout, isRaw: false
        ) else { return nil }
        return ProcessOutput(
            exitCode: raw.exitCode,
            stdout: String(decoding: raw.stdout, as: UTF8.self),
            stderr: String(decoding: raw.stderr, as: UTF8.self)
        )
    }

    public func runRaw(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        standardInput: Data?,
        timeout: TimeInterval
    ) async -> RawProcessOutput? {
        await record(
            executable, arguments, currentDirectory, standardInput, timeout, isRaw: true
        )
    }

    private func record(
        _ executable: String,
        _ arguments: [String],
        _ currentDirectory: String?,
        _ standardInput: Data?,
        _ timeout: TimeInterval,
        isRaw: Bool
    ) async -> RawProcessOutput? {
        let invocation = Invocation(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            standardInput: standardInput,
            timeout: timeout,
            isRaw: isRaw
        )
        invocations.append(invocation)
        inFlight += 1
        maxConcurrentInvocations = max(maxConcurrentInvocations, inFlight)
        defer { inFlight -= 1 }

        let result = byCommandLine[invocation.commandLine]
            ?? byExecutable[executable]
            ?? defaultResult
        if result.delay != .zero {
            try? await Task.sleep(for: result.delay)
        }
        guard !result.isTimeout else { return nil }
        return RawProcessOutput(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}
