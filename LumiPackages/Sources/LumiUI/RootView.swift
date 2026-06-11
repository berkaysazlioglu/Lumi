import LumiKit
import LumiState
import SwiftUI

/// Faz 3 kök görünümü: repo tab'ları + grid layout'lu terminal alanı +
/// minimize şeridi + toast overlay. Sidebar'lar Faz 4, focus mode Faz 6.
public struct RootView: View {
    private let workspace: WorkspaceStore
    private let repoStore: RepoStore
    private let terminals: TerminalListStore
    private let toasts: ToastStore
    private let viewProvider: any TerminalViewProviding

    public init(
        workspace: WorkspaceStore,
        repoStore: RepoStore,
        terminals: TerminalListStore,
        toasts: ToastStore,
        viewProvider: any TerminalViewProviding
    ) {
        self.workspace = workspace
        self.repoStore = repoStore
        self.terminals = terminals
        self.toasts = toasts
        self.viewProvider = viewProvider
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bgDeep)
        .overlay(alignment: .bottomTrailing) {
            ToastOverlay(store: toasts) { terminalID in
                terminals.restoreAndFocus(terminalID)
            }
        }
        .confirmationDialog(
            "Close \(workspace.closeTabDialog?.repoName ?? "")?",
            isPresented: closeTabDialogBinding
        ) {
            Button("Close Tab", role: .destructive) {
                workspace.confirmCloseTab()
            }
            Button("Cancel", role: .cancel) {
                workspace.cancelCloseTab()
            }
        } message: {
            Text("\(workspace.closeTabDialog?.minimizedCount ?? 0) minimized terminal will be killed.")
        }
        .preferredColorScheme(.dark)
    }

    private var closeTabDialogBinding: Binding<Bool> {
        Binding(
            get: { workspace.closeTabDialog != nil },
            set: { isPresented in
                if !isPresented { workspace.cancelCloseTab() }
            }
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            tabStrip
            addRepoButton
            Spacer()
            if let active = workspace.activeTab {
                gridLayoutMenu(for: active)
                Button("New Terminal") {
                    terminals.spawn(in: active)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentVivid)
            }
            Text("\(terminals.totalCount)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        // Sol 80px: traffic light alanı (spec/30 custom titlebar paritesi)
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .background(Theme.bgSurface)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workspace.openTabs, id: \.self) { repoPath in
                    tabChip(for: repoPath)
                }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
    }

    private func tabChip(for repoPath: String) -> some View {
        let isActive = workspace.activeTab == repoPath
        let name = repoStore.repo(at: repoPath)?.name ?? (repoPath as NSString).lastPathComponent
        return HStack(spacing: 6) {
            Button {
                workspace.setActiveTab(repoPath)
            } label: {
                Text(name)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button {
                workspace.requestCloseTab(repoPath, repoName: name)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Theme.bgElevated : Theme.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Theme.accentPrimary : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
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

    private func gridLayoutMenu(for repoPath: String) -> some View {
        let current = workspace.gridLayout(for: repoPath)
        return Menu {
            Button("Auto") {
                workspace.setGridLayout(LumiKit.GridLayout(mode: .auto, count: 2), for: repoPath)
            }
            Menu("Columns") {
                ForEach(2...5, id: \.self) { count in
                    Button("\(count) Columns") {
                        workspace.setGridLayout(LumiKit.GridLayout(mode: .columns, count: count), for: repoPath)
                    }
                }
            }
            Menu("Rows") {
                ForEach(2...5, id: \.self) { count in
                    Button("\(count) Rows") {
                        workspace.setGridLayout(LumiKit.GridLayout(mode: .rows, count: count), for: repoPath)
                    }
                }
            }
        } label: {
            Text(gridLayoutLabel(current))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func gridLayoutLabel(_ layout: LumiKit.GridLayout) -> String {
        switch layout.mode {
        case .auto: return "Auto"
        case .columns: return "\(layout.count) Col"
        case .rows: return "\(layout.count) Row"
        }
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        if let active = workspace.activeTab {
            repoContent(active)
        } else {
            welcomeState
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 12) {
            Text("Lumi")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accentPrimary)
            Text("Bir repo aç ve terminal başlat")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Button("Open Repo") {
                workspace.isRepoSelectorOpen = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func repoContent(_ repoPath: String) -> some View {
        let visible = terminals.visibleTerminals(in: repoPath)
        let minimized = terminals.minimizedTerminals(in: repoPath)
        return VStack(spacing: 8) {
            if !minimized.isEmpty {
                minimizedStrip(minimized)
            }
            if visible.isEmpty {
                emptyRepoState(repoPath)
            } else {
                TerminalGridView(
                    terminals: visible,
                    layout: workspace.gridLayout(for: repoPath),
                    activeTerminalID: terminals.activeTerminalID,
                    viewProvider: viewProvider,
                    onFocus: { terminals.focus($0) },
                    onMinimize: { terminals.minimize($0) },
                    onClose: { terminals.close($0) }
                )
            }
        }
        .padding(12)
    }

    /// Minimize edilen terminaller şeridi — SessionList sidebar'ı Faz 4'e dek
    /// restore yüzeyi. Tıklama yalnız restore eder; odak vermez (spec/21 §6).
    private func minimizedStrip(_ minimized: [TerminalMeta]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Minimized:")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                ForEach(minimized) { meta in
                    Button {
                        terminals.restore(meta.id)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Theme.statusColor(for: meta.status))
                                .frame(width: 6, height: 6)
                            Text(meta.oscTitle ?? meta.task ?? meta.name)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.bgSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(height: 24)
    }

    private func emptyRepoState(_ repoPath: String) -> some View {
        VStack(spacing: 10) {
            Text("Bu repoda terminal yok")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Button("New Terminal") {
                terminals.spawn(in: repoPath)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accentVivid)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
