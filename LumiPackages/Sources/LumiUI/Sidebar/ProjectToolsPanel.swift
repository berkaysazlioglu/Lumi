import LumiKit
import LumiState
import SwiftUI

public struct ProjectToolsPanel: View {
    @Shell private var shell

    /// Seçim `LayoutStore`'dadır (karar 72): view'ın `@State`'i panel her
    /// kapandığında — kenar hover'ıyla açılan geçici panelde her seferinde —
    /// yok oluyor, sekme Explorer'a dönüyordu.
    private var selected: ProjectToolsTab {
        let stored = shell.layout.projectToolsTab
        // Kaydedilen sekme bu repoda yoksa (Source Control'süz proje) Explorer.
        return available.contains(stored) ? stored : .explorer
    }

    private var available: [ProjectToolsTab] {
        ProjectToolsTab.available(isGitRepo: isGitRepo, isPlasticWorkspace: isPlasticWorkspace)
    }

    public init() {}

    private var isGitRepo: Bool {
        guard let path = shell.toolsRepoPath else { return false }
        return shell.repos.capabilities[path]?.isGitRepo ?? shell.repos.repo(at: path)?.isGitRepo ?? false
    }

    /// Karar 46: `.plastic/` kökü Source Control sekmesini Plastic sürümüyle açar.
    private var isPlasticWorkspace: Bool {
        guard let path = shell.toolsRepoPath else { return false }
        return shell.repos.capabilities[path]?.isPlasticWorkspace ?? false
    }

    private var hasSourceControl: Bool { isGitRepo || isPlasticWorkspace }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(available, id: \.self) { tab in
                    Button { shell.layout.setProjectToolsTab(tab) } label: {
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
            if let path = shell.toolsRepoPath {
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
