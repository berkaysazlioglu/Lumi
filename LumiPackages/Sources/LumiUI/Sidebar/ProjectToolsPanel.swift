import LumiKit
import LumiState
import SwiftUI

public struct ProjectToolsPanel: View {
    @Shell private var shell
    @State private var selected: ProjectToolsTab = .explorer

    public init() {}

    private var isGitRepo: Bool {
        guard let path = shell.activeRepoPath else { return false }
        return shell.repos.capabilities[path]?.isGitRepo ?? shell.repos.repo(at: path)?.isGitRepo ?? false
    }

    /// Karar 46: `.plastic/` kökü Source Control sekmesini Plastic sürümüyle açar.
    private var isPlasticWorkspace: Bool {
        guard let path = shell.activeRepoPath else { return false }
        return shell.repos.capabilities[path]?.isPlasticWorkspace ?? false
    }

    private var hasSourceControl: Bool { isGitRepo || isPlasticWorkspace }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(ProjectToolsTab.available(isGitRepo: isGitRepo, isPlasticWorkspace: isPlasticWorkspace), id: \.self) { tab in
                    Button { selected = tab } label: {
                        VStack(spacing: 0) {
                            Image(systemName: tab.icon)
                                .font(Theme.Typography.ui(.base))
                                .frame(maxWidth: .infinity)
                                .frame(height: Theme.Spacing.xxxl)
                            Rectangle().fill(selected == tab ? Theme.accentPrimary : .clear)
                                .frame(height: Theme.Spacing.xxs)
                        }
                        .foregroundStyle(selected == tab ? Theme.textPrimary : Theme.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected == tab ? [.isSelected] : [])
                }
            }
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            Text(selected.title.uppercased())
                .font(Theme.Typography.ui(.label, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            if let path = shell.activeRepoPath {
                switch selected {
                case .explorer: ExplorerView(repoPath: path)
                case .agentHistory: AgentHistoryView(repoPath: path)
                case .sourceControl:
                    // Her iki VCS de varsa Git öncelikli (karar 46).
                    if isGitRepo {
                        SourceControlView(repoPath: path)
                    } else if isPlasticWorkspace {
                        PlasticSourceControlView(repoPath: path)
                    }
                }
            } else {
                EmptyStatePlaceholder("Select a project", density: .inline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bgSurface)
        .foregroundStyle(Theme.textPrimary)
        .environment(\.colorScheme, .dark)
        .onChange(of: hasSourceControl) { if !hasSourceControl && selected == .sourceControl { selected = .explorer } }
        .onChange(of: shell.activeRepoPath) {
            if !hasSourceControl && selected == .sourceControl { selected = .explorer }
        }
    }
}

private extension ProjectToolsTab {
    var title: String {
        switch self {
        case .explorer: "Explorer"
        case .agentHistory: "Agent History"
        case .sourceControl: "Source Control"
        }
    }
    var icon: String {
        switch self {
        case .explorer: "doc.on.doc"
        case .agentHistory: "clock.arrow.circlepath"
        case .sourceControl: "arrow.triangle.branch"
        }
    }
}
