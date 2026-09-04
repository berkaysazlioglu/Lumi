import Foundation
import LumiKit

/// Codex kullanım servisi (karar 32 — Orca paritesi, `codex-fetcher.ts`).
///
/// Akış:
/// 1. **Auth kapısı:** `$CODEX_HOME/auth.json` (yoksa `~/.codex/auth.json`) var mı?
///    Yoksa `codex` HİÇ spawn edilmez. Orca'nın gerekçesi: giriş yapmamış
///    kullanıcıda spawn zaten başarısız olur ve arka planda beklenmedik bir
///    Codex süreci görünür.
/// 2. **RPC:** `codex -c approval_policy=never -s read-only -a never app-server`
///    ile `account/rateLimits/read`. Salt-okunur ve onaysız kip: probe hiçbir şey
///    çalıştırmaz.
///
/// Orca'nın PTY yedeği (`/status` ekranını parse etme) taşınmadı: RPC yolu
/// codex-cli 0.153.2'de doğrulandı ve PTY probe'u kullanıcı görmeden gizli bir
/// terminal açmayı gerektiriyor — bir sonraki karar olarak ertelendi.
public actor CodexUsageService: UsageServicing {
    static let rpcTimeout: TimeInterval = 30
    static let rateLimitsMethod = "account/rateLimits/read"

    public nonisolated var provider: AgentProvider { .codex }

    private let binaryName: String
    private let codexHome: String
    private let locator: any BinaryLocating

    public init(
        binaryName: String = "codex",
        codexHome: String = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex"),
        locator: any BinaryLocating = SystemBinaryLocator()
    ) {
        self.binaryName = binaryName
        self.codexHome = codexHome
        self.locator = locator
    }

    public func fetch() async throws -> UsageSnapshot {
        let authPath = (codexHome as NSString).appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: authPath) else {
            throw LumiError.usageUnavailable(detail: "Codex not signed in")
        }
        guard let binary = await locator.locate(binaryName) else {
            throw LumiError.cliNotFound(binary: binaryName)
        }

        let responseLine: Data
        do {
            responseLine = try await CodexAppServerProbe.requestResponseLine(
                binary: binary,
                method: Self.rateLimitsMethod,
                timeout: Self.rpcTimeout
            )
        } catch let error as CodexAppServerProbe.ProbeError {
            throw LumiError.usageUnavailable(detail: Self.describe(error))
        }

        guard let snapshot = CodexUsageParser.parse(responseLine: responseLine) else {
            throw LumiError.usageUnavailable(detail: "output format not recognized")
        }
        return snapshot
    }

    private static func describe(_ error: CodexAppServerProbe.ProbeError) -> String {
        switch error {
        case .launchFailed:
            return "codex app-server failed to launch"
        case .timedOut:
            return "codex app-server timed out"
        case .exitedEarly(let stderr):
            return stderr.isEmpty ? "codex app-server exited early" : stderr
        case .rpc(let message):
            return message
        }
    }
}
