import Foundation
import LumiKit

/// `buildAgentCommand` portu (spec/13 §3.7): provider remap + flag enjeksiyonu.
/// `claude`/`codex` ile başlamayan içerik (örn. `git pull\r`) DOKUNULMADAN geçer.
/// Temp system-prompt dosyaları UUID adlıdır ve temp dizin uygulama
/// kapanışında topluca silinir (karar 11 — hiç-temizlenmeme bug'ı taşınmaz).
public struct AgentCommandBuilder: Sendable {
    let tempDirectory: URL

    public init(tempDirectory: URL) {
        self.tempDirectory = tempDirectory
    }

    public func build(
        content: String,
        provider: AgentProvider,
        claude: ClaudeAgentConfig?,
        codex: CodexAgentConfig?
    ) throws -> String {
        let remapped = Self.remapProviderCommand(content, provider: provider)
        switch provider {
        case .claude:
            return try buildClaude(remapped, config: claude)
        case .codex:
            return Self.buildCodex(remapped, config: codex)
        }
    }

    /// Satır başındaki `claude` kelimesi seçili provider binary'sine çevrilir.
    static func remapProviderCommand(_ content: String, provider: AgentProvider) -> String {
        guard provider == .codex else { return content }
        guard content == "claude"
            || content.hasPrefix("claude ")
            || content.hasPrefix("claude\r") else {
            return content
        }
        return "codex" + content.dropFirst("claude".count)
    }

    func buildClaude(_ content: String, config: ClaudeAgentConfig?) throws -> String {
        guard let config, content.hasPrefix("claude ") else { return content }

        var flags: [String] = []
        if let systemPrompt = config.systemPrompt {
            let path = try writeTempPromptFile(prefix: "system-prompt", contents: systemPrompt)
            flags.append("--system-prompt-file '\(path)'")
        }
        if let appendPrompt = config.appendSystemPrompt {
            let path = try writeTempPromptFile(prefix: "append-system-prompt", contents: appendPrompt)
            flags.append("--append-system-prompt-file '\(path)'")
        }
        if let model = config.model {
            flags.append("--model \(model)")
        }
        if !config.allowedTools.isEmpty {
            flags.append("--allowedTools " + quotedList(config.allowedTools))
        }
        if !config.disallowedTools.isEmpty {
            flags.append("--disallowedTools " + quotedList(config.disallowedTools))
        }
        if let tools = config.tools {
            flags.append("--tools \"\(tools)\"")
        }
        if let permissionMode = config.permissionMode {
            flags.append("--permission-mode \(permissionMode)")
        }
        if let maxTurns = config.maxTurns {
            flags.append("--max-turns \(maxTurns)")
        }
        guard !flags.isEmpty else { return content }

        // `claude <flags> -- <orijinal prompt>` (spec/13 §3.7)
        let remainder = content.dropFirst("claude".count)
        return "claude " + flags.joined(separator: " ") + " --" + remainder
    }

    static func buildCodex(_ content: String, config: CodexAgentConfig?) -> String {
        guard let model = config?.model,
              content == "codex" || content.hasPrefix("codex ") || content.hasPrefix("codex\r"),
              !content.contains("--model") else {
            return content
        }
        return "codex --model \(model)" + content.dropFirst("codex".count)
    }

    private func quotedList(_ items: [String]) -> String {
        items.map { "\"\($0)\"" }.joined(separator: " ")
    }

    private func writeTempPromptFile(prefix: String, contents: String) throws -> String {
        do {
            try FileManager.default.createDirectory(
                at: tempDirectory, withIntermediateDirectories: true
            )
            let url = tempDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString).txt")
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            throw LumiError.fileOperationFailed(
                path: tempDirectory.path,
                detail: "temp prompt file could not be written: \(error.localizedDescription)"
            )
        }
    }
}
