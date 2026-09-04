import Foundation

/// Timeout'lu bir alt sürecin metin çıktısı.
public struct ProcessOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Binary-güvenli varyantın çıktısı: stdout UTF8'e çevrilmeden döner
/// (görsel blob'ları — `git show sha:file`, karar 21).
public struct RawProcessOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Alt süreç koşturma sınırı (refactor 3.1). Tüm process I/O bu protokolden
/// geçer; servisler `init(runner:)` ile ikame alabilir, böylece git/claude/codex
/// binary'si olmayan bir ortamda da birim testi yazılabilir.
///
/// **Sessiz-fail sözleşmesi:** timeout, başlatma hatası veya iptal `nil` döndürür
/// — hata fırlatılmaz. Çağıran servis bunu kendi hata sözleşmesine map'ler.
public protocol ProcessRunning: Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        standardInput: Data?,
        timeout: TimeInterval
    ) async -> ProcessOutput?

    func runRaw(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        standardInput: Data?,
        timeout: TimeInterval
    ) async -> RawProcessOutput?
}

/// Çağrı yerlerini kısaltan varsayılan aşırı yüklemeler. Protokol
/// gereksinimlerinde default argüman kullanılamadığı için ayrı imzalar.
extension ProcessRunning {
    public func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> ProcessOutput? {
        await run(
            executable, arguments: arguments,
            currentDirectory: nil, standardInput: nil, timeout: timeout
        )
    }

    public func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeout: TimeInterval
    ) async -> ProcessOutput? {
        await run(
            executable, arguments: arguments,
            currentDirectory: currentDirectory, standardInput: nil, timeout: timeout
        )
    }

    public func run(
        _ executable: String,
        arguments: [String],
        standardInput: Data?,
        timeout: TimeInterval
    ) async -> ProcessOutput? {
        await run(
            executable, arguments: arguments,
            currentDirectory: nil, standardInput: standardInput, timeout: timeout
        )
    }

    public func runRaw(
        _ executable: String,
        arguments: [String],
        currentDirectory: String?,
        timeout: TimeInterval
    ) async -> RawProcessOutput? {
        await runRaw(
            executable, arguments: arguments,
            currentDirectory: currentDirectory, standardInput: nil, timeout: timeout
        )
    }
}

/// PATH'ten executable çözme sınırı (refactor 3.1). `which` + bilinen fallback
/// dizinleri; bulunamazsa nil (arıza değil, CLI yoluna düşmek için normal durum).
public protocol BinaryLocating: Sendable {
    func locate(_ name: String, timeout: TimeInterval) async -> String?
}

extension BinaryLocating {
    /// Varsayılan timeout (design/02 §8: `which` 5 sn).
    public static var defaultLocateTimeout: TimeInterval { 5 }

    public func locate(_ name: String) async -> String? {
        await locate(name, timeout: Self.defaultLocateTimeout)
    }
}
