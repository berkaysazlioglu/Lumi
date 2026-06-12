import LumiKit
import LumiState
import SwiftUI

/// Sol sidebar (v1 LeftSidebar paritesi; spec/22 §3). Dikey düzen v1 ile aynı:
/// Sessions (aktif repo'nun terminalleri) → Project Context (file tree, kalan
/// alan) → Personas + Quick Actions. Bölümler 1px border ile ayrılır.
struct LeftSidebarView: View {
    let repoPath: String
    let repoStore: RepoStore
    let terminals: TerminalListStore
    let personasStore: PersonasStore
    let actionsStore: ActionsStore
    let onOpenFile: (String) -> Void
    let onReveal: (String) -> Void
    let onTrash: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            sessionsSection
            divider
            FileTreeSidebar(
                repoPath: repoPath,
                repoStore: repoStore,
                onOpenFile: onOpenFile,
                onReveal: onReveal,
                onTrash: onTrash
            )
            .frame(maxHeight: .infinity)
            divider
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    personasSection
                    actionsSection
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Theme.bgSurface)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }

    // MARK: - Sessions (spec/22 §3.1: aktif repo'nun terminalleri)

    private var sessionsSection: some View {
        let repoTerminals = terminals.terminals(in: repoPath)
        return VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(
                icon: "square.stack.3d.up",
                title: "Sessions",
                count: repoTerminals.isEmpty ? nil : repoTerminals.count
            )
            .padding(.bottom, repoTerminals.isEmpty ? 4 : 8)
            if repoTerminals.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(repoTerminals) { meta in
                            SessionRow(
                                meta: meta,
                                isActive: terminals.activeTerminalID == meta.id,
                                isMinimized: terminals.isMinimized(meta.id)
                            ) {
                                // Minimize ise önce restore, sonra odak (spec/22 §3.1)
                                if terminals.isMinimized(meta.id) {
                                    terminals.restoreAndFocus(meta.id)
                                } else {
                                    terminals.focus(meta.id)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    // MARK: - Personas (spec/13 §2.5: tıkla → o rolde hazır oturum)

    @ViewBuilder
    private var personasSection: some View {
        if !personasStore.personas.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SidebarSectionHeader(icon: "person.2", title: "Personas")
                    .padding(.bottom, 8)
                actionGrid {
                    ForEach(personasStore.personas) { persona in
                        SidebarActionButton(
                            icon: "person.crop.circle",
                            label: persona.label
                        ) {
                            personasStore.spawn(persona.id, repoPath: repoPath)
                        }
                        .help(
                            persona.scope == .project
                                ? "\(persona.label) (project)" : persona.label
                        )
                    }
                }
            }
            .padding(12)
            .overlay(alignment: .bottom) { divider }
        }
    }

    // MARK: - Quick Actions (spec/22 §3.3; v1 action-btn 2 sütun grid)

    private var actionsSection: some View {
        let userActions = actionsStore.actions.filter { $0.scope != .project }
        let projectActions = actionsStore.actions.filter { $0.scope == .project }
        return VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(icon: "bolt", title: "Quick Actions") {
                SidebarHeaderAction(icon: "plus") {
                    actionsStore.createNew(repoPath: repoPath)
                }
                .help("Create action with AI")
            }
            .padding(.bottom, 8)
            actionGrid {
                ForEach(userActions) { action in
                    actionButton(action)
                }
            }
            // v1 .action-divider: user ve project action'ları arasında ince çizgi
            if !userActions.isEmpty, !projectActions.isEmpty {
                divider.padding(.vertical, 8)
            }
            actionGrid {
                ForEach(projectActions) { action in
                    actionButton(action)
                }
            }
        }
        .padding(12)
    }

    private func actionGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            alignment: .leading,
            spacing: 8
        ) {
            content()
        }
    }

    private func actionButton(_ action: Action) -> some View {
        SidebarActionButton(
            icon: Self.iconSymbol(for: action.icon),
            label: action.label
        ) {
            actionsStore.execute(action.id, repoPath: repoPath)
        }
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
}

/// v1 .section-header: accent ikon + 11px uppercase başlık + opsiyonel sayaç
/// badge'i + opsiyonel sağ aksiyon.
struct SidebarSectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var count: Int?
    @ViewBuilder var trailing: () -> Trailing

    init(
        icon: String,
        title: String,
        count: Int? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accentPrimary)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: 0)
            trailing()
        }
    }
}

/// v1 .section-header__action: 20×20 sessiz buton, hover'da elevated + accent.
struct SidebarHeaderAction: View {
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovering ? Theme.accentPrimary : Theme.textMuted)
                .frame(width: 20, height: 20)
                .background(isHovering ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// v1 .session-item: StatusDot + isim; aktif satır elevated zemin + 2px sol
/// accent çizgisi, minimize 0.5 opacity, hover'da aydınlanır.
struct SessionRow: View {
    let meta: TerminalMeta
    let isActive: Bool
    let isMinimized: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.statusColor(for: meta.status))
                    .frame(width: 8, height: 8)
                Text(meta.oscTitle ?? meta.task ?? meta.name)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive || isHovering ? Theme.bgElevated : Color.clear)
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle().fill(Theme.accentPrimary).frame(width: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isMinimized ? 0.5 : 1)
        .onHover { isHovering = $0 }
    }

    private var nameColor: Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}

/// v1 .action-btn: elevated zemin, accent ikon, 11px label; hover'da
/// accent-deep zemin + beyaz içerik.
struct SidebarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isHovering ? Theme.textPrimary : Theme.accentPrimary)
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovering ? Theme.accentDeep : Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
