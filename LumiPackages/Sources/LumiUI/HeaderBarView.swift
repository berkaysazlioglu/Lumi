import LumiKit
import LumiState
import SwiftUI

/// Üst header çubuğu (spec/22 Header; görsel değerler v1 globals.css'ten):
/// 52px, repo tab'leri + repo ekleme solda; grid menüsü, New <Provider>
/// split-dropdown'u ve 32px ikon butonları (sidebar/git/focus/settings) sağda.
struct HeaderBarView: View {
    static let height: CGFloat = 52

    let workspace: WorkspaceStore
    let repoStore: RepoStore
    let terminals: TerminalListStore
    let personasStore: PersonasStore
    let settings: SettingsStore

    var body: some View {
        HStack(spacing: 10) {
            tabStrip
            addRepoButton
            Spacer()
            if let active = workspace.activeTab {
                gridLayoutMenu(for: active)
                newTerminalMenu(for: active)
            }
            HeaderIconButton(
                icon: "sidebar.left",
                isActive: workspace.leftSidebarOpen,
                action: { workspace.toggleLeftSidebar() }
            )
            HeaderIconButton(
                icon: "arrow.triangle.branch",
                isActive: workspace.rightSidebarOpen,
                action: { workspace.toggleRightSidebar() }
            )
            HeaderIconButton(
                icon: "arrow.up.left.and.arrow.down.right",
                isActive: workspace.isFocusMode,
                action: { workspace.toggleFocusMode() }
            )
            HeaderIconButton(
                icon: "gearshape",
                isActive: workspace.isSettingsOpen,
                action: { workspace.isSettingsOpen = true }
            )
            Text("\(terminals.totalCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        // Sol 80px: traffic light alanı (spec/30 custom titlebar paritesi)
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .frame(height: Self.height)
        .background(Theme.bgSurface)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
    }

    // MARK: - Tab'ler

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(workspace.openTabs, id: \.self) { repoPath in
                    RepoTabChip(
                        name: repoStore.repo(at: repoPath)?.name
                            ?? (repoPath as NSString).lastPathComponent,
                        isActive: workspace.activeTab == repoPath,
                        onSelect: { workspace.setActiveTab(repoPath) },
                        onClose: { name in
                            workspace.requestCloseTab(repoPath, repoName: name)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
    }

    private var addRepoButton: some View {
        Button {
            workspace.isRepoSelectorOpen.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accentPrimary)
                .frame(width: 24, height: 24)
                .background(Theme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { workspace.isRepoSelectorOpen },
            set: { workspace.isRepoSelectorOpen = $0 }
        )) {
            RepoSelectorView(groups: repoStore.groupedRepos) { repo in
                workspace.isRepoSelectorOpen = false
                workspace.openTab(repo.path)
            }
        }
    }

    // MARK: - New <Provider> split-dropdown (spec/20 §6: üç spawn yolu)

    private func newTerminalMenu(for repoPath: String) -> some View {
        let provider = settings.current.aiProvider
        return Menu {
            Button("New Bash") {
                // Düz shell; task etiketi kart başlığı olur (spec/20 §6.2)
                terminals.spawn(in: repoPath, task: "Bash")
            }
            if !personasStore.personas.isEmpty {
                Divider()
                ForEach(personasStore.personas, id: \.id) { persona in
                    Button("New \(persona.label)") {
                        personasStore.spawn(persona.id, repoPath: repoPath)
                    }
                }
            }
        } label: {
            Label("New \(provider.displayName)", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
        } primaryAction: {
            terminals.spawn(in: repoPath, command: provider.launchCommand)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accentVivid)
        .fixedSize()
    }

    private func gridLayoutMenu(for repoPath: String) -> some View {
        GridLayoutMenu(
            current: workspace.gridLayout(for: repoPath),
            onSelect: { workspace.setGridLayout($0, for: repoPath) }
        )
    }
}

/// Repo tab'i (v1 globals.css .repo-tab): pasif şeffaf, aktif elevated +
/// accent kenarlık; kapatma butonu yalnız hover'da görünür, hover'ı kırmızı.
struct RepoTabChip: View {
    let name: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (String) -> Void

    @State private var isHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
            Text(name)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            closeButton
                .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(isActive ? Theme.bgElevated : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isActive ? Theme.accentVivid.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }

    private var closeButton: some View {
        Button {
            onClose(name)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isCloseHovering ? Theme.error : Theme.textMuted)
                .frame(width: 18, height: 18)
                .background(isCloseHovering ? Theme.error.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovering = $0 }
    }
}

/// Header sağ ikon butonu (v1 Header.tsx: 32×32, hover'da elevated zemin).
struct HeaderIconButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(isHovering || isActive ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}

/// Grid layout menüsü — header ve FocusModeBar'ın ortak bileşeni (DRY).
struct GridLayoutMenu: View {
    static let countRange = 2...5

    let current: LumiKit.GridLayout
    let onSelect: (LumiKit.GridLayout) -> Void

    var body: some View {
        Menu {
            Button("Auto") {
                onSelect(LumiKit.GridLayout(mode: .auto, count: 2))
            }
            Menu("Columns") {
                ForEach(Self.countRange, id: \.self) { count in
                    Button("\(count) Columns") {
                        onSelect(LumiKit.GridLayout(mode: .columns, count: count))
                    }
                }
            }
            Menu("Rows") {
                ForEach(Self.countRange, id: \.self) { count in
                    Button("\(count) Rows") {
                        onSelect(LumiKit.GridLayout(mode: .rows, count: count))
                    }
                }
            }
        } label: {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var label: String {
        switch current.mode {
        case .auto: return "Auto"
        case .columns: return "\(current.count) Col"
        case .rows: return "\(current.count) Row"
        }
    }
}
