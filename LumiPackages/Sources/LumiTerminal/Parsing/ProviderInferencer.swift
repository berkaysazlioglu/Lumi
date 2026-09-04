import Foundation

/// Input/output/OSC ipuçlarından agent çıkarımı.
/// Asimetri birebir korunur: "openai codex" hint'i her zaman codex'e çevirir;
/// "claude code" yalnızca hint unknown iken claude'a çevirir (codex output ile düşmez).
struct ProviderInferencer {
    /// Her tuş vuruşunda derlenmesin diye önceden derlenir (Faz 1.24).
    private static let codexCommand = CachedRegex("^codex(\\s|$)")
    private static let claudeCommand = CachedRegex("^claude(\\s|$)")

    private(set) var hint: AgentHint = .unknown

    mutating func observeInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.codexCommand.matches(trimmed) {
            hint = .codex
        } else if Self.claudeCommand.matches(trimmed) {
            hint = .claude
        }
    }

    /// Sıcak yol: her output chunk'ında çağrılır. `lowercased()` kopyası yerine
    /// case-insensitive arama kullanılır; hint codex ise hiçbir kalıp durumu
    /// değiştiremez (asimetri) — erken çıkılır.
    mutating func observeOutput(_ text: String) {
        guard hint != .codex else { return }
        if text.range(of: "openai codex", options: .caseInsensitive) != nil {
            hint = .codex
            return
        }
        if hint == .unknown, text.range(of: "claude code", options: .caseInsensitive) != nil {
            hint = .claude
        }
    }

    mutating func applyOSCHint(_ newHint: AgentHint) {
        guard newHint != .unknown else { return }
        hint = newHint
    }
}
