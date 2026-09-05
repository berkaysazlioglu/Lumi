public enum ProjectToolsTab: String, CaseIterable, Sendable {
    case explorer
    case agentHistory
    case sourceControl

    public static func available(isGitRepo: Bool) -> [ProjectToolsTab] {
        isGitRepo ? allCases : [.explorer, .agentHistory]
    }
}
