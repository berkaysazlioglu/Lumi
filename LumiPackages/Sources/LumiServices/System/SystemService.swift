import AppKit
import Foundation
import LumiKit

/// Sistem sağlığı + platform yardımcıları (design/02 §8, spec/13 §5-6).
public final class SystemService: SystemServicing {
    static let commandTimeout: TimeInterval = 5

    private let smokeTester: (any TerminalSmokeTesting)?
    private let opener: @Sendable (URL) -> Void
    // FileManager.default thread-safe'tir ama Sendable işaretli değil
    private var fileManager: FileManager { .default }

    public init(
        smokeTester: (any TerminalSmokeTesting)? = nil,
        opener: @escaping @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.smokeTester = smokeTester
        self.opener = opener
    }

    // MARK: - PATH düzeltmesi (spec/13 platform; birebir + async)

    public func fixProcessPath() async {
        let environment = ProcessInfo.processInfo.environment
        var entries: [String] = []

        let shell = environment["SHELL"] ?? "/bin/zsh"
        if let result = await ProcessRunner.run(
            shell,
            arguments: ["-ilc", "echo -n \"$PATH\""],
            timeout: Self.commandTimeout
        ), result.exitCode == 0 {
            entries += result.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ":")
                .map(String.init)
        }
        entries += (environment["PATH"] ?? "").split(separator: ":").map(String.init)

        let home = NSHomeDirectory()
        let knownDirectories = [
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "\(home)/.nvm/current/bin",
            "\(home)/.volta/bin",
        ]
        entries += knownDirectories.filter { fileManager.fileExists(atPath: $0) }

        var seen = Set<String>()
        let merged = entries.filter { !$0.isEmpty && seen.insert($0).inserted }
        setenv("PATH", merged.joined(separator: ":"), 1)
    }

    // MARK: - Sistem check'leri (spec/13 §5; Electron'a özgü check'ler düşürüldü)

    public func runChecks(selectedProvider: AgentProvider) async -> [SystemCheckResult] {
        var results: [SystemCheckResult] = []

        let shellCandidates = ["/bin/zsh", "/bin/bash", "/bin/sh"]
        if let shell = shellCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            results.append(SystemCheckResult(
                id: "shell", label: "Login shell", status: .pass, message: shell
            ))
        } else {
            results.append(SystemCheckResult(
                id: "shell", label: "Login shell", status: .fail,
                message: "No usable shell found (zsh/bash/sh)"
            ))
        }

        if let smokeTester {
            do {
                try await smokeTester.runSmokeTest()
                results.append(SystemCheckResult(
                    id: "pty", label: "PTY", status: .pass, message: "PTY spawn OK"
                ))
            } catch {
                results.append(SystemCheckResult(
                    id: "pty", label: "PTY", status: .fail,
                    message: "PTY smoke test failed: \(error.localizedDescription)"
                ))
            }
        }

        for provider in [AgentProvider.claude, AgentProvider.codex] {
            let binary = provider.rawValue
            if let found = await locateBinary(binary) {
                results.append(SystemCheckResult(
                    id: "\(binary)-cli", label: "\(binary) CLI", status: .pass, message: found
                ))
            } else if provider == selectedProvider {
                results.append(SystemCheckResult(
                    id: "\(binary)-cli", label: "\(binary) CLI", status: .fail,
                    message: "\(binary) not found in PATH", isFixable: true
                ))
            } else {
                results.append(SystemCheckResult(
                    id: "\(binary)-cli", label: "\(binary) CLI", status: .warn,
                    message: "\(binary) not found (not selected provider)"
                ))
            }
        }

        return results
    }

    private func locateBinary(_ name: String) async -> String? {
        await BinaryLocator.locate(name, timeout: Self.commandTimeout)
    }

    // MARK: - Shell/dosya yardımcıları

    public func openExternal(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw LumiError.externalURLBlocked(url)
        }
        opener(url)
    }

    public func trash(path: String) async throws {
        do {
            try fileManager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        } catch {
            throw LumiError.fileOperationFailed(path: path, detail: error.localizedDescription)
        }
    }

    public func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @MainActor
    public func chooseFolder() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
