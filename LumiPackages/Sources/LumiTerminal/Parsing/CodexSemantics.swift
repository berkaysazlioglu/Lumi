/// Codex'e özgü OSC 9 semantiği: turn/task tamamlanma ve idle kalıpları.
/// Codex title yaymadığından bu semantik 0/2'ye dokunmaz.
struct CodexSemantics: OSCSemantics {
    private static let turnComplete =
        CachedRegex("\\b(turn|task)\\s+(complete|completed|done|finished)\\b")
    /// Literal kalıplar — regex derlemesine gerek yok, `contains` yeterli.
    private static let idleMarkers = ["waiting for input", "all idle", "idle state"]

    func interpret(code: Int, payload: String, hint: AgentHint) -> [OSCEvent] {
        guard code == 9, isTurnComplete(payload) else { return [] }
        return [.notification(.codexTurnComplete)]
    }

    func isTurnComplete(_ payload: String) -> Bool {
        let lower = payload.lowercased()
        if Self.turnComplete.matches(lower) { return true }
        return Self.idleMarkers.contains { lower.contains($0) }
    }
}
