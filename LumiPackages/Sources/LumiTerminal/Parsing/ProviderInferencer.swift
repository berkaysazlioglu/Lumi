import Foundation

/// Input/output/OSC ipuçlarından agent çıkarımı (spec/10 §6).
/// Asimetri birebir korunur: "openai codex" hint'i her zaman codex'e çevirir;
/// "claude code" yalnızca hint unknown iken claude'a çevirir (codex output ile düşmez).
struct ProviderInferencer {
    private(set) var hint: AgentHint = .unknown

    mutating func observeInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^codex(\\s|$)", options: .regularExpression) != nil {
            hint = .codex
        } else if trimmed.range(of: "^claude(\\s|$)", options: .regularExpression) != nil {
            hint = .claude
        }
    }

    mutating func observeOutput(_ text: String) {
        let lower = text.lowercased()
        if hint != .codex, lower.contains("openai codex") {
            hint = .codex
        }
        if hint == .unknown, lower.contains("claude code") {
            hint = .claude
        }
    }

    mutating func applyOSCHint(_ newHint: AgentHint) {
        guard newHint != .unknown else { return }
        hint = newHint
    }
}
