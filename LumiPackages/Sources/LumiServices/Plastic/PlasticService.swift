import Foundation
import LumiKit

/// Plastic SCM `cm` CLI servisi (karar 45). Git gibi CLI yaklaşımı: kullanıcının
/// `cm` kimlik/sunucu yapılandırmasıyla otomatik uyumlu, Plastic'in .NET
/// kütüphanelerine bağımlılık yok.
///
/// `actor` (design/02 §11): çağrılar arası durum tutar — `cm` binary'sinin
/// çözümlenmiş yolu bir kez bulunur ve saklanır (`which` her çağrıda koşmaz).
/// Komut koşumu `ProcessRunning`, binary çözümü `BinaryLocating` üzerinden.
public actor PlasticService: PlasticServicing {
    public static let executableName = "cm"
    /// `cm find` sunucuya gider (cloud); git'in 20 sn'sinden geniş tutuldu.
    public static let commandTimeout: TimeInterval = 30
    /// `--dateformat`: ISO 8601 + saat dilimi — locale'den bağımsız parse.
    public static let dateFormat = "yyyy-MM-ddTHH:mm:sszzz"
    /// Alan ayracı ASCII unit separator (0x1F): `{tab}` token'ı `cm find`de
    /// geçersiz, `|`/sekme yorumda geçebilir; kontrol karakteri argv'den aynen geçer.
    static let changesetFormat = ["{changesetid}", "{branch}", "{owner}", "{date}", "{parent}", "{comment}"]
        .joined(separator: String(PlasticOutputParser.changesetFieldSeparator))

    private let runner: any ProcessRunning
    private let locator: any BinaryLocating
    private let guardian: RepoPathGuard
    private let timeout: TimeInterval
    /// `.some(nil)` = arandı, bulunamadı; `nil` = henüz aranmadı.
    private var resolvedExecutable: String??

    public init(
        runner: any ProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator(),
        pathGuard: RepoPathGuard = RepoPathGuard(),
        timeout: TimeInterval = PlasticService.commandTimeout
    ) {
        self.runner = runner
        self.locator = locator
        self.guardian = pathGuard
        self.timeout = timeout
    }

    // MARK: - PlasticReading

    public func isCLIAvailable() async -> Bool {
        await executable() != nil
    }

    public func workspaceInfo(workspacePath: String) async -> PlasticWorkspaceInfo? {
        guard let header = await run(["status", "--header", "--machinereadable", "--fieldseparator=|"], in: workspacePath, operation: "status --header") else {
            return nil
        }
        guard let parsed = PlasticOutputParser.parseHeader(header) else {
            logQuietFailure("status --header", detail: "beklenmeyen çıktı: \(header.prefix(120))")
            return nil
        }
        let selector = await run(["showselector"], in: workspacePath, operation: "showselector")
        return PlasticWorkspaceInfo(
            changesetID: parsed.changesetID,
            repository: parsed.repository,
            server: parsed.server,
            branch: selector.flatMap(PlasticOutputParser.parseSelectorBranch)
        )
    }

    public func status(workspacePath: String) async -> [PlasticFileChange] {
        let arguments = ["status", "--short", "--machinereadable", "--fieldseparator=|", "--all", "--cutignored"]
        guard let stdout = await run(arguments, in: workspacePath, operation: "status") else { return [] }
        return PlasticOutputParser.parseStatus(stdout, workspacePath: workspacePath)
    }

    public func recentChangesets(workspacePath: String, limit: Int) async -> [PlasticChangeset] {
        let query = "changesets order by changesetid desc limit \(max(1, limit))"
        let arguments = [
            "find", query,
            "--format=\(Self.changesetFormat)",
            "--dateformat=\(Self.dateFormat)",
            "--nototal",
        ]
        guard let stdout = await run(arguments, in: workspacePath, operation: "find changesets") else { return [] }
        return PlasticOutputParser.parseChangesets(stdout)
    }

    // MARK: - PlasticWriting

    public func checkin(workspacePath: String, message: String, files: [String]) async throws {
        guard !files.isEmpty else {
            throw LumiError.plasticFailed(operation: "checkin", detail: "No files selected")
        }
        let paths = try files.map { try guardian.resolve(repoPath: workspacePath, relativePath: $0) }
        // `--all`: verilen path'lerdeki changed/moved/deleted; `--applychanged`:
        // checkout edilmemiş değişiklikler; `--private`: kontrolsüz öğeler de
        // eklenir (ayrı `cm add` gerekmez). Path'ler HER ZAMAN verilir — aksi
        // halde `--private` tüm çalışma alanını gönderirdi.
        let arguments = ["checkin"] + paths + ["-c=\(message)", "--all", "--applychanged", "--private", "--noshowchangeset"]
        try await runThrowing(arguments, in: workspacePath, operation: "checkin")
    }

    public func undo(workspacePath: String, files: [String]) async throws {
        guard !files.isEmpty else {
            throw LumiError.plasticFailed(operation: "undo", detail: "No files selected")
        }
        let paths = try files.map { try guardian.resolve(repoPath: workspacePath, relativePath: $0) }
        try await runThrowing(["undo"] + paths, in: workspacePath, operation: "undo")
    }

    /// Yazma yolu: `cm` yoksa `cliNotFound`, exit ≠ 0 ise `plasticFailed`
    /// (detay stderr, boşsa stdout; 500 karakter). `cm` hatayı stderr'e
    /// `Error: …` önekiyle yazar ve exit 1 döner.
    private func runThrowing(_ arguments: [String], in workspacePath: String, operation: String) async throws {
        guard let executable = await executable() else {
            throw LumiError.cliNotFound(binary: Self.executableName)
        }
        let output = await runner.run(
            executable,
            arguments: arguments,
            currentDirectory: workspacePath,
            standardInput: nil,
            timeout: timeout
        )
        guard let output else {
            throw LumiError.plasticFailed(operation: operation, detail: "timeout")
        }
        guard output.exitCode == 0 else {
            let detail = output.stderr.isEmpty ? output.stdout : output.stderr
            throw LumiError.plasticFailed(
                operation: operation,
                detail: String(detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            )
        }
    }

    // MARK: - Koşum

    private func executable() async -> String? {
        if let resolved = resolvedExecutable { return resolved }
        let located = await locator.locate(Self.executableName)
        resolvedExecutable = .some(located)
        return located
    }

    /// Başarılı koşunun stdout'u; `cm` yoksa, exit ≠ 0 ise ya da timeout'ta nil.
    private func run(_ arguments: [String], in workspacePath: String, operation: String) async -> String? {
        guard let executable = await executable() else { return nil }
        let output = await runner.run(
            executable,
            arguments: arguments,
            currentDirectory: workspacePath,
            standardInput: nil,
            timeout: timeout
        )
        guard let output, output.exitCode == 0 else {
            // Çalışma alanı olmayan dizin BEKLENEN durumdur — log gürültüsü yok.
            if let output, output.stderr.contains("is not in a workspace") || output.stdout.contains("is not in a workspace") {
                return nil
            }
            let detail = output.map { "exit \($0.exitCode): \($0.stderr.prefix(200))" } ?? "timeout/launch failure"
            logQuietFailure(operation, detail: detail)
            return nil
        }
        return output.stdout
    }

    private nonisolated func logQuietFailure(_ operation: String, detail: String) {
        fputs("[lumi-plastic] \(operation) başarısız (sessiz): \(detail)\n", stderr)
    }
}
