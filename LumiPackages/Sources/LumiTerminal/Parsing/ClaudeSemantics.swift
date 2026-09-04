/// Claude Code'a özgü OSC semantiği:
/// - OSC 0/2: ✳ (U+2733) idle işareti ve `claude` kelime sınırı → hint + durum
/// - OSC 9: "needs your permission" → karar bekleme sinyali (turn-complete DEĞİL)
struct ClaudeSemantics: OSCSemantics {
    private static let claudeWord = CachedRegex("\\bclaude\\b")
    private static let permissionWord = CachedRegex("\\bpermission\\b")

    func interpret(code: Int, payload: String, hint: AgentHint) -> [OSCEvent] {
        if OSCTitleInterpreter.titleCodes.contains(code) {
            guard isClaudeTitle(payload) else { return [] }
            return [.title(OSCTitleInterpreter.event(raw: payload, hint: .claude))]
        }
        if code == 9, isPermissionRequest(payload) {
            return [.notification(.permissionRequest)]
        }
        return []
    }

    /// İzin kalıbı turn-complete'ten ÖNCE sınanır (zincir sırası): kuyruk
    /// "karar bekliyor"da duraklar, "turn bitti"de akar.
    func isPermissionRequest(_ payload: String) -> Bool {
        let lower = payload.lowercased()
        return lower.contains("needs your permission") || Self.permissionWord.matches(lower)
    }

    private func isClaudeTitle(_ raw: String) -> Bool {
        if OSCTitleInterpreter.hasIdleMark(raw) { return true }
        let lower = raw.lowercased()
        return lower.contains("claude code") || Self.claudeWord.matches(lower)
    }
}
