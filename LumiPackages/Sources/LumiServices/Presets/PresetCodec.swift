import Foundation
import LumiKit
import Yams

/// Persona/Action YAML çözümleme (spec/13 §2.1, §3.1).
/// Lenient: zorunlu alanlar (persona: id+label; action: id+label+steps)
/// eksikse dosya SESSİZCE atlanır (nil); parse hataları da nil döner.
enum PresetCodec {
    // MARK: - Persona

    static func decodePersona(_ yaml: String, scope: PresetScope) -> Persona? {
        guard let dict = loadDictionary(yaml) else { return nil }
        guard let id = dict["id"] as? String, !id.isEmpty,
              let label = dict["label"] as? String, !label.isEmpty else {
            return nil
        }
        return Persona(
            id: id,
            label: label,
            provider: (dict["provider"] as? String).flatMap(AgentProvider.init(rawValue:)),
            claude: decodeClaudeConfig(dict["claude"]),
            codex: decodeCodexConfig(dict["codex"]),
            scope: scope
        )
    }

    // MARK: - Action

    static func decodeAction(
        _ yaml: String,
        scope: PresetScope,
        isDefault: Bool = false
    ) -> Action? {
        guard let dict = loadDictionary(yaml) else { return nil }
        guard let id = dict["id"] as? String, !id.isEmpty,
              let label = dict["label"] as? String, !label.isEmpty,
              let rawSteps = dict["steps"] as? [Any], !rawSteps.isEmpty else {
            return nil
        }
        let steps = rawSteps.compactMap(decodeStep)
        guard !steps.isEmpty else { return nil }

        return Action(
            id: id,
            label: label,
            description: dict["description"] as? String,
            icon: (dict["icon"] as? String) ?? Action.defaultIcon,
            provider: (dict["provider"] as? String).flatMap(AgentProvider.init(rawValue:)),
            claude: decodeClaudeConfig(dict["claude"]),
            codex: decodeCodexConfig(dict["codex"]),
            steps: steps,
            modifiedAt: stringValue(dict["modified_at"]),
            scope: scope,
            isDefault: isDefault
        )
    }

    /// Yalnız `modified_at` varlığı kontrolü — seed asimetrisi için
    /// (parse-broken dosya nil döndüğünden "ezilebilir" sayılır).
    static func hasModifiedAt(_ yaml: String) -> Bool {
        guard let dict = loadDictionary(yaml) else { return false }
        return stringValue(dict["modified_at"]) != nil
    }

    static func actionID(in yaml: String) -> String? {
        loadDictionary(yaml)?["id"] as? String
    }

    private static func decodeStep(_ raw: Any) -> ActionStep? {
        guard let dict = raw as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        switch type {
        case "write":
            guard let content = dict["content"] as? String else { return nil }
            return .write(content: content)
        case "wait_for":
            guard let pattern = dict["pattern"] as? String else { return nil }
            let timeout = intValue(dict["timeout"]) ?? ActionStep.defaultWaitTimeoutMs
            return .waitFor(pattern: pattern, timeoutMs: timeout)
        case "delay":
            guard let ms = intValue(dict["ms"]) else { return nil }
            return .delay(ms: ms)
        default:
            return nil
        }
    }

    // MARK: - Ortak bloklar

    private static func decodeClaudeConfig(_ raw: Any?) -> ClaudeAgentConfig? {
        guard let dict = raw as? [String: Any] else { return nil }
        return ClaudeAgentConfig(
            systemPrompt: dict["systemPrompt"] as? String,
            appendSystemPrompt: dict["appendSystemPrompt"] as? String,
            model: dict["model"] as? String,
            allowedTools: stringArray(dict["allowedTools"]),
            disallowedTools: stringArray(dict["disallowedTools"]),
            tools: dict["tools"] as? String,
            permissionMode: dict["permissionMode"] as? String,
            maxTurns: intValue(dict["maxTurns"])
        )
    }

    private static func decodeCodexConfig(_ raw: Any?) -> CodexAgentConfig? {
        guard let dict = raw as? [String: Any] else { return nil }
        return CodexAgentConfig(model: dict["model"] as? String)
    }

    private static func loadDictionary(_ yaml: String) -> [String: Any]? {
        guard let loaded = try? Yams.load(yaml: yaml) else { return nil }
        return loaded as? [String: Any]
    }

    private static func stringArray(_ raw: Any?) -> [String] {
        (raw as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        return nil
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String { return value }
        if let date = raw as? Date {
            // Yams quote'suz ISO timestamp'i Date'e çevirir — string'e geri döndür
            return ISO8601DateFormatter().string(from: date)
        }
        return nil
    }
}
