import LumiKit
import SwiftUI

/// Repo keşfi + varsayılan sağlayıcı (Faz 7.3).
struct GeneralSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .general

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LumiSectionTitle(
                title: "General",
                description: "Repo discovery and default AI provider."
            )
            LumiField(
                title: "Projects Root",
                hint: "First-level subdirectories are listed as repos"
            ) {
                projectsRootField
            }
            LumiField(
                title: "Additional Paths",
                hint: "root: subdirectories are scanned · repo: added on its own"
            ) {
                additionalPathsField
            }
            LumiField(
                title: "AI Provider",
                hint: "CLI used for new terminals and actions",
                isLast: true
            ) {
                LumiSegmented(
                    options: [
                        .init(value: AgentProvider.claude, label: "Claude"),
                        .init(value: AgentProvider.codex, label: "Codex"),
                    ],
                    selection: Binding(
                        get: { shell.settings.current.aiProvider },
                        set: { shell.settings.setProvider($0) }
                    )
                )
            }
        }
    }

    private var projectsRootField: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(shell.settings.current.projectsRoot.isEmpty
                ? "(not set)" : shell.settings.current.projectsRoot)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            LumiBrowseButton(icon: "folder", label: "Browse") {
                Task { @MainActor in
                    if let path = await shell.actions.chooseFolder() {
                        shell.settings.setProjectsRoot(path)
                    }
                }
            }
        }
    }

    private var additionalPathsField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                LumiBrowseButton(icon: "folder", label: "Add Root Directory") {
                    addPath(type: .root)
                }
                LumiBrowseButton(icon: "folder.badge.gearshape", label: "Add Repository") {
                    addPath(type: .repo)
                }
            }
            if !shell.settings.current.additionalPaths.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(shell.settings.current.additionalPaths) { entry in
                        additionalPathRow(entry)
                    }
                }
            }
        }
    }

    private func additionalPathRow(_ entry: AdditionalPath) -> some View {
        let isRoot = entry.type == .root
        return HStack(spacing: Theme.Spacing.md) {
            Badge(
                text: entry.type.rawValue.uppercased(),
                color: isRoot ? Theme.accentPrimary : Theme.accentCyan
            )
            Text(entry.path)
                .font(Theme.Typography.bodyMono)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            IconButton(
                systemName: "xmark",
                label: "Remove \(entry.path)",
                size: .tiny,
                side: 24
            ) {
                shell.settings.removeAdditionalPath(id: entry.id)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(minHeight: Theme.Spacing.xxxl)
        .background(Theme.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func addPath(type: AdditionalPath.PathType) {
        Task { @MainActor in
            if let path = await shell.actions.chooseFolder() {
                shell.settings.addAdditionalPath(path, type: type)
            }
        }
    }
}

#if DEBUG
#Preview("General") {
    SettingsTabPreview(.general)
}
#endif
