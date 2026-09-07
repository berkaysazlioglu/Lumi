public enum ProjectToolsTab: String, CaseIterable, Sendable {
    case explorer
    case agentHistory
    case sourceControl

    /// Source Control sekmesi Git reposunda VEYA Plastic SCM çalışma alanında
    /// görünür (karar 39 + 45).
    public static func available(isGitRepo: Bool, isPlasticWorkspace: Bool = false) -> [ProjectToolsTab] {
        isGitRepo || isPlasticWorkspace ? allCases : [.explorer, .agentHistory]
    }
}
