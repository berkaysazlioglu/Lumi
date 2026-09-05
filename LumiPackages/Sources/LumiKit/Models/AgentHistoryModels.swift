import Foundation

/// Bir oturumdaki tek konuşma turu (kullanıcı ya da asistan metni).
///
/// Tool çağrıları (`tool_use` / `tool_result`) ve düşünme blokları tur
/// sayılmaz — Agent History yalnız okunabilir konuşmayı gösterir.
public struct AgentHistoryTurn: Identifiable, Sendable, Equatable {
    public enum Role: String, Sendable, Equatable, CaseIterable {
        case user
        case assistant
    }

    public let role: Role
    public let text: String
    public let timestamp: Date?

    public init(role: Role, text: String, timestamp: Date? = nil) {
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    /// `ForEach` için kararlı kimlik — aynı içerik hep aynı kimliği verir.
    public var id: String {
        "\(role.rawValue)|\(timestamp?.timeIntervalSince1970 ?? 0)|\(text.prefix(64))"
    }

    /// Metni `limit` karakterle kırpar (kırpılmışsa "…" ekler).
    public func truncated(to limit: Int) -> AgentHistoryTurn {
        guard text.count > limit else { return self }
        return AgentHistoryTurn(role: role, text: String(text.prefix(limit)) + "…", timestamp: timestamp)
    }
}

public struct AgentHistoryEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let provider: AgentProvider
    public let sessionID: String
    public let title: String
    /// Liste satırındaki özet — son konuşma turunun metni.
    public let preview: String?
    public let updatedAt: Date
    public let cwd: String?
    public let logPath: String
    /// Oturumun ilk gördüğü git dalı (Claude `gitBranch`, Codex `git.branch`).
    public let gitBranch: String?
    /// Son asistan mesajının modeli (ham ad; sunum için `modelLabel`).
    public let model: String?
    /// Örneklenen transkriptteki kullanıcı+asistan mesaj sayısı.
    public let messageCount: Int
    /// Oturumu başlatan ilk gerçek kullanıcı istemi (meta satırları hariç).
    public let firstPrompt: String?
    /// Son konuşma turları (en fazla 3, her biri kırpılmış).
    public let recentTurns: [AgentHistoryTurn]

    public init(provider: AgentProvider, sessionID: String, title: String, preview: String? = nil,
                updatedAt: Date, cwd: String? = nil, logPath: String,
                gitBranch: String? = nil, model: String? = nil, messageCount: Int = 0,
                firstPrompt: String? = nil, recentTurns: [AgentHistoryTurn] = []) {
        self.id = "\(provider.rawValue):\(sessionID)"
        self.provider = provider
        self.sessionID = sessionID
        self.title = title
        self.preview = preview
        self.updatedAt = updatedAt
        self.cwd = cwd
        self.logPath = logPath
        self.gitBranch = gitBranch
        self.model = model
        self.messageCount = messageCount
        self.firstPrompt = firstPrompt
        self.recentTurns = recentTurns
    }

    public var resumeCommand: String? {
        guard sessionID.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$"#, options: .regularExpression) != nil else { return nil }
        let quoted = sessionID.replacingOccurrences(of: "'", with: "'\\''")
        return provider == .claude ? "claude --resume '\(quoted)'" : "codex resume '\(quoted)'"
    }

    /// Metadata satırında gösterilen kısa model adı:
    /// `claude-opus-4-1` → `opus-4-1`, `claude-sonnet-4-20250514` → `sonnet-4`.
    public var modelLabel: String? {
        guard let model, !model.isEmpty else { return nil }
        var label = model.hasPrefix("claude-") ? String(model.dropFirst("claude-".count)) : model
        if let last = label.split(separator: "-").last, last.count == 8, last.allSatisfy(\.isNumber) {
            label = String(label.dropLast(last.count + 1))
        }
        return label.isEmpty ? nil : label
    }
}
