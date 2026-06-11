import LumiKit
import LumiState
import SwiftUI

/// Kök görünüm: repo tab'ları + sol file-tree / sağ git sidebar'ları +
/// grid layout'lu terminal alanı + FileViewer modal + toast overlay.
/// Focus mode Faz 6.
public struct RootView: View {
    /// File tree context-menü aksiyonları — composition root bağlar
    /// (view'lar servis görmez, design/00 §3).
    public struct FileActions {
        public let reveal: (String, String) -> Void // (repoPath, relativePath)
        public let trash: (String, String) -> Void

        public init(
            reveal: @escaping (String, String) -> Void,
            trash: @escaping (String, String) -> Void
        ) {
            self.reveal = reveal
            self.trash = trash
        }
    }

    /// Settings/onboarding'in sistem etkileşimleri (NSOpenPanel, system checks).
    public struct ShellActions {
        public let chooseFolder: () async -> String?
        public let runChecks: () async -> [SystemCheckResult]
        public let fixCheck: (String) -> Void

        public init(
            chooseFolder: @escaping () async -> String?,
            runChecks: @escaping () async -> [SystemCheckResult],
            fixCheck: @escaping (String) -> Void
        ) {
            self.chooseFolder = chooseFolder
            self.runChecks = runChecks
            self.fixCheck = fixCheck
        }
    }

    private let workspace: WorkspaceStore
    private let repoStore: RepoStore
    private let terminals: TerminalListStore
    private let gitStore: GitStore
    private let fileViewer: FileViewerStore
    private let personasStore: PersonasStore
    private let actionsStore: ActionsStore
    private let settings: SettingsStore
    private let toasts: ToastStore
    private let viewProvider: any TerminalViewProviding
    private let highlighter: any SyntaxHighlighting
    private let fileActions: FileActions
    private let shellActions: ShellActions

    public init(
        workspace: WorkspaceStore,
        repoStore: RepoStore,
        terminals: TerminalListStore,
        gitStore: GitStore,
        fileViewer: FileViewerStore,
        personasStore: PersonasStore,
        actionsStore: ActionsStore,
        settings: SettingsStore,
        toasts: ToastStore,
        viewProvider: any TerminalViewProviding,
        highlighter: any SyntaxHighlighting,
        fileActions: FileActions,
        shellActions: ShellActions
    ) {
        self.workspace = workspace
        self.repoStore = repoStore
        self.terminals = terminals
        self.gitStore = gitStore
        self.fileViewer = fileViewer
        self.personasStore = personasStore
        self.actionsStore = actionsStore
        self.settings = settings
        self.toasts = toasts
        self.viewProvider = viewProvider
        self.highlighter = highlighter
        self.fileActions = fileActions
        self.shellActions = shellActions
    }

    public var body: some View {
        Group {
            if workspace.isOnboardingActive {
                OnboardingView(settings: settings, shell: shellActions) {
                    workspace.isOnboardingActive = false
                }
            } else {
                dashboard
            }
        }
        .preferredColorScheme(.dark)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            // Focus mode: header gizlenir, hover-reveal bar devralır (spec/22)
            if !workspace.isFocusMode {
                headerBar
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bgDeep)
        .overlay(alignment: .top) {
            if workspace.isFocusMode, let active = workspace.activeTab {
                FocusModeBar(workspace: workspace, terminals: terminals, repoPath: active)
            }
        }
        .overlay {
            if fileViewer.isPresented {
                FileViewerView(store: fileViewer, highlighter: highlighter)
            }
        }
        .overlay {
            if workspace.isSettingsOpen {
                SettingsView(
                    settings: settings,
                    chooseFolder: shellActions.chooseFolder,
                    onClose: { workspace.isSettingsOpen = false }
                )
            }
        }
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
        .confirmationDialog(
            "Quit Lumi?",
            isPresented: quitDialogBinding
        ) {
            Button("Quit", role: .destructive) {
                workspace.resolveQuit(true)
            }
            Button("Cancel", role: .cancel) {
                workspace.resolveQuit(false)
            }
        } message: {
            Text("\(workspace.quitDialogTerminalCount ?? 0) açık terminal kapatılacak.")
        }
    }

    private var quitDialogBinding: Binding<Bool> {
        Binding(
            get: { workspace.quitDialogTerminalCount != nil },
            set: { isPresented in
                if !isPresented, workspace.quitDialogTerminalCount != nil {
                    workspace.resolveQuit(false)
                }
            }
        )
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
            sidebarToggle(
                icon: "sidebar.left",
                isOn: workspace.leftSidebarOpen,
                action: { workspace.toggleLeftSidebar() }
            )
            sidebarToggle(
                icon: "sidebar.right",
                isOn: workspace.rightSidebarOpen,
                action: { workspace.toggleRightSidebar() }
            )
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

    private func sidebarToggle(
        icon: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? Theme.accentPrimary : Theme.textMuted)
                .frame(width: 24, height: 24)
                .background(isOn ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - İçerik

    @ViewBuilder
    private var mainArea: some View {
        if let active = workspace.activeTab {
            HStack(spacing: 0) {
                if workspace.leftSidebarOpen && !workspace.isFocusMode {
                    LeftSidebarView(
                        repoPath: active,
                        repoStore: repoStore,
                        personasStore: personasStore,
                        actionsStore: actionsStore,
                        onOpenFile: { path in
                            Task { await fileViewer.presentView(repoPath: active, filePath: path) }
                        },
                        onReveal: { path in fileActions.reveal(active, path) },
                        onTrash: { path in fileActions.trash(active, path) }
                    )
                    .frame(width: 280)
                    Rectangle().fill(Theme.border).frame(width: 1)
                }

                repoContent(active)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if workspace.rightSidebarOpen && !workspace.isFocusMode {
                    Rectangle().fill(Theme.border).frame(width: 1)
                    GitSidebar(
                        repoPath: active,
                        gitStore: gitStore,
                        onSelectCommit: { commit in
                            Task { await fileViewer.presentCommit(repoPath: active, commit: commit) }
                        },
                        onShowFileDiff: { path in
                            Task { await fileViewer.presentDiff(repoPath: active, filePath: path) }
                        }
                    )
                    .frame(width: 280)
                }
            }
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
