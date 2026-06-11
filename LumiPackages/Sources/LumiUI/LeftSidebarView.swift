import LumiKit
import LumiState
import SwiftUI

/// Sol sidebar (spec/22): Personas + Quick Actions + Project Context (file tree).
struct LeftSidebarView: View {
    let repoPath: String
    let repoStore: RepoStore
    let personasStore: PersonasStore
    let actionsStore: ActionsStore
    let onOpenFile: (String) -> Void
    let onReveal: (String) -> Void
    let onTrash: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    personasSection
                    actionsSection
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 260)
            Rectangle().fill(Theme.border).frame(height: 1)
            FileTreeSidebar(
                repoPath: repoPath,
                repoStore: repoStore,
                onOpenFile: onOpenFile,
                onReveal: onReveal,
                onTrash: onTrash
            )
        }
        .background(Theme.bgSurface)
    }

    // MARK: - Personas (spec/13 §2.5: tıkla → o rolde hazır oturum)

    private var personasSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionHeader("PERSONAS")
            ForEach(personasStore.personas) { persona in
                Button {
                    personasStore.spawn(persona.id, repoPath: repoPath)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accentPrimary)
                        Text(persona.label)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        if persona.scope == .project {
                            scopeBadge("project")
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick Actions (spec/13 §3)

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                sectionHeader("ACTIONS")
                Spacer()
                Button {
                    actionsStore.createNew(repoPath: repoPath)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accentPrimary)
                }
                .buttonStyle(.plain)
                .help("Create action with AI")
                .padding(.trailing, 12)
            }
            ForEach(actionsStore.actions) { action in
                actionRow(action)
            }
        }
    }

    private func actionRow(_ action: Action) -> some View {
        Button {
            actionsStore.execute(action.id, repoPath: repoPath)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Self.iconSymbol(for: action.icon))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentVivid)
                Text(action.label)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if action.isDefault {
                    scopeBadge("default")
                } else if action.scope == .project {
                    scopeBadge("project")
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action.description ?? action.label)
        .contextMenu {
            Button("Edit with AI") {
                actionsStore.edit(
                    action.id,
                    projectPath: action.scope == .project ? repoPath : nil
                )
            }
            if let versions = actionsStore.histories[action.id], !versions.isEmpty {
                Menu("Restore Version") {
                    ForEach(versions) { version in
                        Button(version.timestamp) {
                            actionsStore.restore(action.id, version: version.timestamp)
                        }
                    }
                }
            }
            // Default'lar silinemez — watcher reseed'le geri getirir (spec/13 §3.5)
            if !action.isDefault {
                Button("Delete", role: .destructive) {
                    actionsStore.delete(
                        action.id,
                        scope: action.scope,
                        projectPath: action.scope == .project ? repoPath : nil
                    )
                }
            }
        }
    }

    /// Lucide ikon adı → SF Symbol (spec/13 ikon rehberi).
    static func iconSymbol(for lucideName: String) -> String {
        switch lucideName {
        case "Terminal": return "terminal"
        case "TestTube": return "testtube.2"
        case "Package": return "shippingbox"
        case "GitBranch": return "arrow.triangle.branch"
        case "FileEdit": return "square.and.pencil"
        default: return "bolt"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private func scopeBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.accentPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.accentPrimary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
