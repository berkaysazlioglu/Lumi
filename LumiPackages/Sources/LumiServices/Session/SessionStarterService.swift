import Foundation
import LumiKit

/// Zamanlanmış oturum başlatıcı (UsageService deseni): `claude` binary'sini çöz
/// → `-p "<prompt>"` ile headless spawn et → 5 saatlik kullanım penceresini
/// başlat. Çalışan terminallere dokunmaz; tek seferlik arka plan isteğidir.
///
/// Not (design/05 §1): çağrı SUBAGENT ile YAPILMAZ — doğrudan binary spawn'ı
/// (token maliyeti yok; yalnız abonelik kotasından düşer). I/O ağırlıklı → `actor`.
public actor SessionStarterService: SessionStarterServicing {
    /// `claude -p` bir tam turn çalıştırıp döner; trivial prompt hızlıdır ama
    /// model/yük değişkenliğine pay bırakırız (asılı kalmaya karşı tavan).
    static let startTimeout: TimeInterval = 120

    private let binaryName: String

    public init(binaryName: String = "claude") {
        self.binaryName = binaryName
    }

    public func start(prompt: String) async throws {
        guard let binary = await BinaryLocator.locate(binaryName) else {
            throw LumiError.cliNotFound(binary: binaryName)
        }

        // arguments dizisi → shell yok, prompt tek argv olarak güvenle geçer.
        guard let output = await ProcessRunner.run(
            binary, arguments: ["-p", prompt], timeout: Self.startTimeout
        ) else {
            throw LumiError.sessionStartFailed(
                detail: "\(binaryName) -p timed out or failed to launch"
            )
        }

        guard output.exitCode == 0 else {
            let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.sessionStartFailed(
                detail: stderr.isEmpty ? "exit code \(output.exitCode)" : stderr
            )
        }
    }
}
