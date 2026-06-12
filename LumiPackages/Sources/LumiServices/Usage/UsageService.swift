import Foundation
import LumiKit

/// Claude kullanım servisi (design/05 §6): `claude` binary'sini çöz → `-p
/// "/usage"` ile spawn et → stdout'u `UsageOutputParser` ile parse et.
/// I/O ağırlıklı, UI-yüzlü değil → `actor`. Hata tek tip `LumiError` (karar 5).
///
/// Not (design/05 §1): çağrı SUBAGENT ile YAPILMAZ — doğrudan binary spawn'ı
/// (token maliyeti yok; yalnız abonelik kotasından düşer).
public actor UsageService: UsageServicing {
    /// Asılı kalmaya karşı timeout (design/05 §2: macOS'ta `timeout` yok,
    /// kendi zamanlayıcımız `ProcessRunner` içinde).
    static let fetchTimeout: TimeInterval = 15

    private let binaryName: String

    public init(binaryName: String = "claude") {
        self.binaryName = binaryName
    }

    public func fetch() async throws -> UsageSnapshot {
        guard let binary = await BinaryLocator.locate(binaryName) else {
            throw LumiError.cliNotFound(binary: binaryName)
        }

        guard let output = await ProcessRunner.run(
            binary, arguments: ["-p", "/usage"], timeout: Self.fetchTimeout
        ) else {
            throw LumiError.usageUnavailable(detail: "\(binaryName) -p /usage timed out or failed to launch")
        }

        guard output.exitCode == 0 else {
            let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.usageUnavailable(
                detail: stderr.isEmpty ? "exit code \(output.exitCode)" : stderr
            )
        }

        guard !output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LumiError.usageUnavailable(detail: "empty output")
        }

        let snapshot = UsageOutputParser.parse(output.stdout)
        // mod tanınamadı VE hiçbir pencere yoksa → biçim tanınmadı (design/05).
        if snapshot.mode == .unknown, !snapshot.hasAnyWindow {
            throw LumiError.usageUnavailable(detail: "output format not recognized")
        }
        return snapshot
    }
}
