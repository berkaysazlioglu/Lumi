import Foundation
import LumiKit

/// Orchestrator'ın Codex tarafı (karar 123): etkileşimli Codex TUI'sinin
/// açılış script'ini yazar ve çalışan konuşmaya `codex queue` ile mesaj bırakır.
///
/// Codex yalnız Lumi'nin MCP araçlarıyla çalışır:
/// - Yerleşik araçlar kapalı (`--disable shell_tool …`, `web_search="disabled"`);
///   kullanıcının kendi MCP sunucuları da bu oturumda `enabled=false`.
/// - `--approve-for-me`: Codex'in auto modu — onaylar otomatik incelemeden
///   geçer, MCP çağrıları kullanıcıya sorulmaz (karar 123: onay kapısı yok).
/// - Talimat `developer_instructions`'tır; her açılışta yeniden üretilir.
///
/// Komut uzun olduğu için shell'e değil `~/.lumi/orchestrator/launch.sh`'a
/// yazılır (0700) ve terminale yalnız `exec /bin/sh <script>` yazılır — Codex
/// çıkınca terminal de kapanır. MCP token'ı script'te değil PTY ortamındadır.
public actor CodexOrchestratorLauncher: OrchestratorLaunching {
    public static let binaryName = "codex"
    public static let tokenEnvironmentKey = "LUMI_MCP_TOKEN"
    static let scriptName = "launch.sh"
    static let queueTimeout: TimeInterval = 30
    static let mcpListTimeout: TimeInterval = 10
    static let envBinary = "/usr/bin/env"

    /// Orchestrator'ın görmemesi gereken Codex yetenekleri: shell, dosya,
    /// görsel, alt ajan, eklenti/uygulama, tarayıcı, bilgisayar kullanımı…
    /// (2026-10-23, codex-cli 0.163 ile canlı doğrulandı: dosya okuyamıyor/yazamıyor).
    static let disabledFeatures = [
        "shell_tool", "unified_exec", "view_image", "multi_agent", "apps", "plugins",
        "image_generation", "browser_use", "computer_use", "in_app_browser", "goals",
        "tool_suggest", "skill_search", "sleep_tool", "memories",
    ]

    private let workingDirectory: URL
    private let runner: any ProcessRunning
    private let locator: any BinaryLocating

    public init(
        workingDirectory: URL,
        runner: any ProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator()
    ) {
        self.workingDirectory = workingDirectory
        self.runner = runner
        self.locator = locator
    }

    // MARK: - OrchestratorLaunching

    public func prepare(_ request: OrchestratorLaunchRequest) async throws -> OrchestratorLaunchPlan {
        let binary = try await codexBinary()
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let foreignServers = await userMCPServers(binary: binary, codexHome: request.codexHome)
        let arguments = Self.arguments(for: request, disabledServers: foreignServers)
        let script = workingDirectory.appendingPathComponent(Self.scriptName)
        try Self.writeExecutable(Self.script(binary: binary, arguments: arguments), to: script)

        var environment: [String: String] = [:]
        if let home = request.codexHome { environment["CODEX_HOME"] = home }
        if let control = request.control { environment[Self.tokenEnvironmentKey] = control.token }
        return OrchestratorLaunchPlan(command: "exec /bin/sh " + shellQuoted(script.path), environment: environment)
    }

    public func queue(_ message: String, thread: String, codexHome: String?) async throws {
        let binary = try await codexBinary()
        let output = await runner.run(
            Self.envBinary,
            arguments: Self.environmentPrefix(codexHome) + [binary, "queue", "--thread", thread, "--message", message],
            currentDirectory: workingDirectory.path,
            standardInput: nil,
            timeout: Self.queueTimeout
        )
        guard let output else {
            throw LumiError.orchestratorQueueFailed(detail: "codex queue timed out or failed to launch")
        }
        guard output.exitCode == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LumiError.orchestratorQueueFailed(
                detail: detail.isEmpty ? "exit code \(output.exitCode)" : String(detail.prefix(300))
            )
        }
    }

    // MARK: - Komut

    static func arguments(for request: OrchestratorLaunchRequest, disabledServers: [String]) -> [String] {
        var args: [String] = []
        if let thread = request.resumeThreadID { args += ["resume", thread] }
        args += ["--approve-for-me"]
        for feature in disabledFeatures { args += ["--disable", feature] }
        args += ["-c", #"web_search="disabled""#]
        // Açılıştaki "Update now?" sorusu orchestrator'ı bekletmesin; Codex'i
        // kullanıcı kendi terminalinde günceller.
        args += ["-c", "check_for_update_on_startup=false"]
        for server in disabledServers {
            args += ["-c", "mcp_servers.\(tomlString(server)).enabled=false"]
        }
        if let control = request.control {
            let server = "mcp_servers.\(OrchestratorTools.serverName)"
            args += [
                "-c", "\(server).url=\(tomlString(control.url))",
                "-c", "\(server).bearer_token_env_var=\(tomlString(tokenEnvironmentKey))",
            ]
        }
        args += ["-c", "developer_instructions=\(tomlString(request.instructions))"]
        return args
    }

    static func script(binary: String, arguments: [String]) -> String {
        """
        #!/bin/sh
        # Lumi orchestrator (karar 123) — generated on every launch; do not edit.
        exec \(([binary] + arguments).map(shellQuoted).joined(separator: " \\\n  "))

        """
    }

    /// TOML temel dizgesi: `-c` değeri TOML olarak ayrıştırılır.
    static func tomlString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    static func environmentPrefix(_ codexHome: String?) -> [String] {
        codexHome.map { ["CODEX_HOME=\($0)"] } ?? []
    }

    // MARK: - Yardımcılar

    private func codexBinary() async throws -> String {
        guard let binary = await locator.locate(Self.binaryName) else {
            throw LumiError.cliNotFound(binary: Self.binaryName)
        }
        return binary
    }

    /// Kullanıcının kendi MCP sunucuları — orchestrator'da kapatılır ki tek
    /// araç kaynağı Lumi olsun. Okunamazsa boş liste (açılış engellenmez).
    private func userMCPServers(binary: String, codexHome: String?) async -> [String] {
        let output = await runner.run(
            Self.envBinary,
            arguments: Self.environmentPrefix(codexHome) + [binary, "mcp", "list", "--json"],
            currentDirectory: workingDirectory.path,
            standardInput: nil,
            timeout: Self.mcpListTimeout
        )
        guard let output, output.exitCode == 0 else { return [] }
        return Self.serverNames(fromMCPList: output.stdout).filter { $0 != OrchestratorTools.serverName }
    }

    static func serverNames(fromMCPList json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return entries.compactMap { $0["name"] as? String }
    }

    /// Script baştan 0700 doğar — talimat proje yollarını taşır.
    private static func writeExecutable(_ text: String, to url: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        guard fileManager.createFile(
            atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o700]
        ) else {
            throw LumiError.fileOperationFailed(path: url.path, detail: "could not write the launch script")
        }
    }
}
