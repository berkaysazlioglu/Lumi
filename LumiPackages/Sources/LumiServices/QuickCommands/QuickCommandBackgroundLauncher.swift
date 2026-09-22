import Foundation
import LumiKit

/// `Start App` script'ini arka planda başlatır (karar 93).
///
/// Ayrı bir süreç API'si yerine mevcut `ProcessRunning` kapısı kullanılır:
/// `/bin/sh -c 'cd … || exit 1; nohup /bin/sh <script> >log 2>&1 </dev/null &'`
/// arka plan işini bırakıp HEMEN çıkar, bu yüzden bekleme kısadır ve
/// cooperative pool'u tutmaz (karar 86). `cd` BİLEREK ana kabuktadır: `cd && nohup … &`
/// yazılsaydı `&` zincirin tamamını, çıktı pipe'ını açık tutan bir alt kabuğa
/// atardı ve başlatıcı script bitene kadar dönmezdi; ayrıca olmayan dizin
/// böylece çıkış koduyla görünür hata olur. Yollar `$1…$3` konumsal argüman
/// olarak geçer — tırnaklama/enjeksiyon derdi yoktur. Arka plan süreci
/// launchd'ye devredilir; Lumi kapansa da yaşar. PATH, açılıştaki
/// `PathEnvironmentFixer` düzeltmesinden miras alınır.
public actor QuickCommandBackgroundLauncher: QuickCommandBackgroundLaunching {
    public static let shell = "/bin/sh"
    /// Başlatıcı `&` ile hemen döner; üst sınır yalnız asılmaya karşı.
    public static let timeout: TimeInterval = 10
    /// Script bittiğinde çıkış kodu log'un sonuna yazılır: arka planda sessizce
    /// kapanan bir Start App (ör. stdin isteyen bir CLI) log'dan teşhis edilir.
    static let launcherScript =
        #"cd "$1" || exit 1; nohup /bin/sh -c '/bin/sh "$1"; echo "[lumi] exited with status $?"' lumi-start-app "$2" >"$3" 2>&1 </dev/null &"#

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func launch(scriptPath: String, workingDirectory: String, logPath: String) async throws {
        let output = await runner.run(
            Self.shell,
            arguments: Self.arguments(scriptPath: scriptPath, workingDirectory: workingDirectory, logPath: logPath),
            timeout: Self.timeout
        )
        guard let output else {
            throw LumiError.spawnFailed(reason: "background launcher timed out or failed to start")
        }
        guard output.exitCode == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.spawnFailed(reason: detail.isEmpty ? "exit code \(output.exitCode)" : String(detail.prefix(500)))
        }
    }

    static func arguments(scriptPath: String, workingDirectory: String, logPath: String) -> [String] {
        ["-c", launcherScript, "lumi-start-app", workingDirectory, scriptPath, logPath]
    }
}
