#if DEBUG
import AppKit
import Foundation
import LumiKit
import LumiState
import SwiftUI

/// `#Preview` altyapısı (Faz 7.7).
///
/// **Neden burada?** `Tests/LumiTestSupport`'taki fake'ler bir test hedefidir;
/// ürün hedefi ona bağlanamaz (bağlansaydı test ikameleri release binary'sine
/// sızardı). Bu yüzden preview'ların ihtiyacı olan LumiKit protokollerinin
/// **en küçük** implementasyonları burada, `#if DEBUG` arkasında durur:
/// hiçbir davranış taşımazlar, yalnız derlenebilir bir bağlam kurarlar.
///
/// Kullanım:
/// ```swift
/// #Preview { SomeView().environment(\.shell, ShellContext.preview()) }
/// ```
public extension ShellContext {
    /// Tamamen sahte servislerle kurulmuş, tek repo'lu bir kabuk bağlamı.
    @MainActor
    static func preview(repoPath: String = "/Users/preview/Projects/lumi") -> ShellContext {
        let config = PreviewConfigService()
        let terminal = PreviewTerminalService()
        let viewProvider = PreviewTerminalViewProvider()
        let git = PreviewGitService()
        let shared = SharedStores.make(config: config, terminal: terminal, viewProvider: viewProvider)
        let repos = RepoStore(service: PreviewRepoService())
        let context = ShellContext(
            navigation: shared.navigation,
            layout: shared.layout,
            dialogs: shared.dialogs,
            terminals: shared.terminals,
            repos: repos,
            workspaces: ProjectWorkspaceStore(service: PreviewWorkspaceService(), config: config, repos: repos, toasts: shared.toasts),
            quickCommands: QuickCommandStore(config: config, generator: PreviewQuickCommandGenerator(),
                scripts: PreviewQuickCommandScripts(), launcher: PreviewQuickCommandLauncher(), toasts: shared.toasts),
            git: GitStore(git: git, toasts: shared.toasts),
            plastic: PlasticStore(service: PreviewPlasticService(), toasts: shared.toasts),
            commitAssistant: CommitMessageAssistant(generator: PreviewCommitMessageGenerator(), toasts: shared.toasts),
            agentHistory: AgentHistoryStore(
                service: PreviewAgentHistoryService(), transfer: PreviewAgentSessionTransfer(), toasts: shared.toasts
            ),
            fileViewer: FileViewerStore(git: git, toasts: shared.toasts),
            settings: shared.settings,
            remote: RemoteStore(service: PreviewRemoteService()),
            sessionSchedule: SessionScheduleStore(starter: PreviewSessionStarterService()),
            promptQueue: PromptQueueStore(service: terminal, toasts: shared.toasts),
            toasts: shared.toasts,
            onboarding: OnboardingStore(
                system: PreviewSystemService(),
                settings: shared.settings,
                toasts: shared.toasts,
                onComplete: {}
            ),
            usage: [:],
            deepSeek: DeepSeekStore(service: PreviewDeepSeekEnvironmentService(), toasts: shared.toasts),
            deepSeekBalance: .preview,
            claudeAccounts: ClaudeAccountStore(
                service: PreviewClaudeAccountService(), toasts: shared.toasts
            ),
            codexAccounts: CodexAccountStore(
                service: PreviewCodexAccountService(), toasts: shared.toasts
            ),
            terminalLinks: TerminalLinkActionStore(
                terminals: shared.terminals, repos: repos,
                workspaces: ProjectWorkspaceStore(
                    service: PreviewWorkspaceService(), config: config, repos: repos, toasts: shared.toasts
                )
            ),
            computerAwake: ComputerAwakeStore(
                terminals: shared.terminals, settings: shared.settings, assertion: PreviewSleepAssertion()
            ),
            resourceUsage: ResourceUsageStore(
                terminals: shared.terminals, terminalService: terminal, sampler: PreviewProcessSampler()
            ),
            viewProvider: viewProvider,
            highlighter: PreviewHighlighter(),
            actions: ShellActions(
                chooseFolder: { repoPath },
                reveal: { _, _ in },
                trash: { _, _ in }
            )
        )
        context.navigation.openTab(repoPath)
        return context
    }
}

/// Settings sekmelerinin ortak preview kabı — panel genişliği ve zemini
/// gerçek modaldakiyle aynı olsun diye.
struct SettingsTabPreview: View {
    private let tab: SettingsTab

    init(_ tab: SettingsTab) { self.tab = tab }

    var body: some View {
        ScrollView {
            tab.content
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.vertical, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 560)
        .background(Theme.bgSurface)
        .environment(\.shell, ShellContext.preview())
    }
}

// MARK: - Minimal in-module fake'ler

private actor PreviewWorkspaceService: WorkspaceServicing {
    func inspect(project: Repo) async throws -> WorkspaceSource {
        WorkspaceSource(projectPath: project.path, scm: .git, branch: "main", revision: "abc123",
                        destinationDirectory: "/Users/preview/lumi/workspaces/\(project.name)")
    }
    func branches(project: Repo, limit: Int) async throws -> [WorkspaceBranch] {
        [WorkspaceBranch(name: "main"), WorkspaceBranch(name: "feature/preview")]
    }
    func create(_ request: WorkspaceCreateRequest) async throws -> WorkspaceCreateResult {
        throw WorkspaceFailure("Creation is unavailable in previews.")
    }
    func copyLibrary(sourcePath: String, workspacePath: String) async throws {}
    func remove(_ workspace: ProjectWorkspace, force: Bool) async throws {}
}

/// Diskte hiçbir şey yoktur; değerler bellekte tutulur.
private actor PreviewConfigService: ConfigServicing {
    private var storedConfig = AppConfig.defaults
    private var storedUIState = UIState.defaults

    func config() -> AppConfig { storedConfig }

    func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) throws {
        mutate(&storedConfig)
    }

    func uiState() -> UIState { storedUIState }

    func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) async {
        mutate(&storedUIState)
    }

    func isFirstRun() -> Bool { false }

    func flushPendingWrites() {}

    nonisolated func events() -> AsyncStream<ConfigEvent> { AsyncStream { _ in } }
}

@MainActor
private final class PreviewTerminalService: TerminalServicing {
    private(set) var terminals: [TerminalMeta] = []

    @discardableResult
    func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        try spawn(repoPath: repoPath, task: task, command: command, environment: [:])
    }

    @discardableResult
    func spawn(
        repoPath: String,
        task: String?,
        command: String?,
        environment: [String: String]
    ) throws -> TerminalMeta {
        let meta = TerminalMeta(
            id: TerminalID(),
            name: "Terminal \(terminals.count + 1)",
            repoPath: repoPath,
            createdAt: Date(),
            task: task
        )
        terminals.append(meta)
        return meta
    }

    func write(id: TerminalID, text: String) throws {}
    func kill(id: TerminalID) throws {}
    func processID(for id: TerminalID) -> Int32? { nil }
    func setAgentHookEndpoint(_ endpoint: AgentHookEndpoint?) {}
    func setLaunchEnvironment(_ environment: [String: String], for provider: AgentProvider) {}
    func applyAgentHookEvent(_ event: AgentHookEvent) {}
    func killAll() {}
    func resize(id: TerminalID, cols: Int, rows: Int) {}
    func setFocused(_ id: TerminalID?) {}
    func setWindowFocused(_ focused: Bool) {}
    func setSurfaceState(_ state: TerminalSurfaceState, for id: TerminalID) {}
    func setSurfaceState(_ state: TerminalSurfaceState, in repoPath: String?) {}
    func events() -> AsyncStream<TerminalEvent> { AsyncStream { _ in } }
    func shutdown() {}
    func applyFont(_ font: NSFont) {}
    func applyCursor(shape: TerminalCursorShape, blink: Bool) {}

    // MARK: - Remote mirror
    private let remoteOutputBroadcaster = EventBroadcaster<Data>()
    func subscribeOutput(_ id: TerminalID) -> AsyncStream<Data> { remoteOutputBroadcaster.stream() }
    func writeInput(_ data: Data, to id: TerminalID) {}
    func serializeScrollback(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int) { (Data(), 0, 0) }
    func applyLinkActions(enabled: Bool) {}
}

@MainActor
private final class PreviewSleepAssertion: SleepAsserting {
    private(set) var isPreventingSleep = false
    func setPreventingSleep(_ prevent: Bool, reason: String) -> Bool {
        isPreventingSleep = prevent
        return true
    }
}

/// İki hesaplı, ikincisi aktif bir liste — Settings ▸ Accounts önizlemesi
/// boş görünmesin (karar 56).
private struct PreviewClaudeAccountService: ClaudeAccountServicing {
    private static let snapshot = ClaudeAccountsSnapshot(
        accounts: [
            ClaudeAccount(
                id: "personal", email: "dev@example.com", organizationName: "Personal",
                createdAt: .distantPast, updatedAt: .distantPast, lastAuthenticatedAt: .distantPast
            ),
            ClaudeAccount(
                id: "work", email: "dev@company.com", organizationName: "Company",
                createdAt: .distantPast, updatedAt: .distantPast, lastAuthenticatedAt: .distantPast
            ),
        ],
        selection: .account("work")
    )

    func accounts() async -> ClaudeAccountsSnapshot { Self.snapshot }
    func syncActiveSelection() async {}
    func addAccount() async throws -> ClaudeAccountsSnapshot { Self.snapshot }
    func cancelPendingLogin() async {}
    func reauthenticate(accountID: String) async throws -> ClaudeAccountsSnapshot { Self.snapshot }
    func removeAccount(accountID: String) async throws -> ClaudeAccountsSnapshot { Self.snapshot }
    func select(_ selection: ClaudeAccountSelection) async throws -> ClaudeAccountsSnapshot {
        ClaudeAccountsSnapshot(accounts: Self.snapshot.accounts, selection: selection)
    }
}

private struct PreviewCodexAccountService: CodexAccountServicing {
    private static let snapshot = CodexAccountsSnapshot(
        accounts: [CodexAccount(
            id: UUID().uuidString, email: "codex@example.com", workspaceName: "Personal",
            createdAt: .distantPast, updatedAt: .distantPast, lastAuthenticatedAt: .distantPast
        )],
        selection: .systemDefault,
        systemDefaultEmail: "default@example.com"
    )
    func accounts() async -> CodexAccountsSnapshot { Self.snapshot }
    func syncActiveSelection() async {}
    func syncManagedHooks(enabled: Bool) async {}
    func addAccount() async throws -> CodexAccountsSnapshot { Self.snapshot }
    func cancelPendingLogin() async {}
    func reauthenticate(accountID: String) async throws -> CodexAccountsSnapshot { Self.snapshot }
    func removeAccount(accountID: String) async throws -> CodexAccountsSnapshot { Self.snapshot }
    func select(_ selection: CodexAccountSelection) async throws -> CodexAccountsSnapshot {
        CodexAccountsSnapshot(accounts: Self.snapshot.accounts, selection: selection)
    }
    func selectedHome() async -> String { "/Users/preview/.codex" }
    func resolvedResumeHome(_ persistedHome: String?) async -> String? {
        persistedHome ?? "/Users/preview/.codex"
    }
}

private struct PreviewDeepSeekEnvironmentService: DeepSeekEnvironmentServicing {
    func read() async -> DeepSeekSetup {
        DeepSeekSetup(envFilePath: "/Users/preview/.claude/deepseek.env", apiKey: nil)
    }

    func install(apiKey: String) async throws -> DeepSeekSetup {
        DeepSeekSetup(envFilePath: "/Users/preview/.claude/deepseek.env", apiKey: apiKey)
    }

    func remove() async throws -> DeepSeekSetup {
        DeepSeekSetup(envFilePath: "/Users/preview/.claude/deepseek.env", apiKey: nil)
    }
}

private struct PreviewProcessSampler: ProcessSampling {
    func sampleProcessTable() async -> ProcessTable? { .empty }
}

@MainActor
private final class PreviewTerminalViewProvider: TerminalViewProviding {
    func attachView(for id: TerminalID, into container: NSView) {}
    func detachView(for id: TerminalID, from container: NSView) {}
    func isAttached(_ id: TerminalID) -> Bool { false }
    func detachAll() {}
    func refreshAttachedViews() {}
}

private struct PreviewAgentSessionTransfer: AgentSessionTransferring {
    func exportSession(_ entry: AgentHistoryEntry, to destination: URL) async throws {}
    func importSession(from source: URL, projectPath: String) async throws -> AgentSessionImportResult {
        AgentSessionImportResult(provider: .claude, sessionID: "preview", logPath: "/tmp/preview.jsonl", subagentCount: 0, didRenameSession: false)
    }
}

private struct PreviewAgentHistoryService: AgentHistoryServicing {
    func deleteSession(_ entry: AgentHistoryEntry) async throws {}
    func entries(projectPath: String) async throws -> [AgentHistoryEntry] { [] }
}

private actor PreviewRepoService: RepoServicing {
    func searchContents(repoPath: String, paths: [String], query: ExplorerContentQuery) async throws -> ExplorerContentResult { ExplorerContentResult() }
    func editFile(repoPath: String, edit: ExplorerFileEdit) async throws {}
    func capabilities(repoPath: String) async -> ProjectCapabilities { ProjectCapabilities(isGitRepo: true) }
    func repos() -> [Repo] { [] }
    func setRoots(projectsRoot: String, additionalPaths: [AdditionalPath]) {}
    func fileTree(repoPath: String) -> [FileTreeNode] { [] }
    func watchFileTree(repoPath: String) {}
    func unwatchFileTree(repoPath: String) {}
    nonisolated func events() -> AsyncStream<RepoEvent> { AsyncStream { _ in } }
}

private struct PreviewPlasticService: PlasticServicing {
    func checkin(workspacePath: String, message: String, files: [String]) async throws {}
    func undo(workspacePath: String, files: [String]) async throws {}
    func undoUnchanged(workspacePath: String) async throws {}
    func isCLIAvailable() async -> Bool { false }
    func workspaceInfo(workspacePath: String) async -> PlasticWorkspaceInfo? { nil }
    func status(workspacePath: String) async -> [PlasticFileChange] { [] }
    func recentChangesets(workspacePath: String, limit: Int) async -> [PlasticChangeset] { [] }
    func workingTreeDiffText(workspacePath: String, changesetID: Int, changes: [PlasticFileChange]) async -> String { "" }
}

private struct PreviewQuickCommandLauncher: QuickCommandBackgroundLaunching {
    func launch(scriptPath: String, workingDirectory: String, logPath: String) async throws {}
}

private struct PreviewQuickCommandScripts: QuickCommandScriptWriting {
    func writeScript(named fileName: String, contents: String) async throws -> String { "/tmp/\(fileName)" }
}

private struct PreviewQuickCommandGenerator: QuickCommandGenerating {
    func generate(_ request: QuickCommandGenerationRequest) async throws -> String { "cd \"{path}\"\nls\n" }
}

private struct PreviewCommitMessageGenerator: CommitMessageGenerating {
    func generate(_ request: CommitMessageRequest) async throws -> String { "Update \(request.changes.count) files" }
}

private struct PreviewGitService: GitServicing {
    func workingTreeDiffText(repoPath: String, files: [String]) async -> String { "" }
    func branches(repoPath: String) async -> [GitBranch] { [] }
    func commits(repoPath: String, branch: String?) async -> [GitCommit] { [] }
    func history(repoPath: String, limit: Int) async -> [GitCommit] { PreviewSamples.history }
    func remoteURL(repoPath: String) async -> String? { "git@github.com:lumi/lumi.git" }
    func isGitHubCLIAvailable() async -> Bool { true }
    func branchSummary(repoPath: String) async -> GitBranchSummary? { GitBranchSummary(upstream: "origin/main", ahead: 2, insertions: 4612, deletions: 691) }
    func status(repoPath: String) async -> [GitFileChange] { [] }
    func commitFiles(repoPath: String, sha: String) async -> [CommitFile] { [] }

    func imagePreview(repoPath: String, file: String, sha: String?) async -> ImagePreview {
        ImagePreview(filePath: file, before: nil, after: nil)
    }

    /// Boş metin yerine örnek içerik: FileViewer preview'ı boş bir panel değil,
    /// gerçek bir belge gösterir.
    func readFile(repoPath: String, file: String) async throws -> String {
        PreviewSamples.markdown
    }

    func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff {
        PreviewSamples.diff(filePath: file)
    }

    func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff {
        PreviewSamples.diff(filePath: file)
    }

    func commit(repoPath: String, message: String, files: [String]) async throws {}
}

/// Sağlayıcı başına sabit bir yüzde döndürür; ağ/CLI yoktur.
private struct PreviewUsageService: UsageServicing {
    let provider: AgentProvider
    let percent: Int

    func fetch() async throws -> UsageSnapshot {
        UsageSnapshot(
            limits: [
                UsageLimit(
                    kind: .session,
                    rawLabel: "Current session",
                    window: window(percent)
                ),
                UsageLimit(
                    kind: .weeklyAll,
                    rawLabel: "Current week (all models)",
                    window: window(min(100, percent + 21))
                ),
            ],
            mode: .subscription,
            fetchedAt: Date()
        )
    }

    /// 5 saatlik pencerenin 3 saati kalmış → tempo çizgisi %40'ta durur
    /// (karar 74); yalnız Codex gerçekte süre bildirir, preview ikisinde de
    /// çizgiyi gösterir.
    private func window(_ percent: Int) -> UsageWindow {
        UsageWindow(
            percentUsed: percent,
            resetsAt: Date().addingTimeInterval(3 * 60 * 60),
            resetsRaw: "in 3h",
            timezone: nil,
            duration: 5 * 60 * 60
        )
    }
}

// MARK: - Örnek veriler

/// Preview'ların paylaştığı örnek içerikler. Tek yerde durur: aynı diff hem
/// `SideBySideDiffView` hem `MarkdownDiffView` hem FileViewer preview'ında
/// kullanılır.
enum PreviewSamples {
    /// Merge'lü, ref'li küçük bir graph — `CommitGraphView` önizlemesi.
    static let history: [GitCommit] = {
        func commit(
            _ hash: String, _ subject: String,
            parents: [String], refs: [GitRef] = [], minutesAgo: Int
        ) -> GitCommit {
            GitCommit(
                hash: hash,
                shortHash: String(hash.prefix(7)),
                message: subject,
                author: "Ada Lovelace",
                date: Date().addingTimeInterval(TimeInterval(-60 * minutesAgo)),
                parentHashes: parents,
                references: refs
            )
        }
        return [
            commit(
                "a1b2c3d4e5f6", "feat: commit graph", parents: ["b1", "c1"],
                refs: [
                    GitRef(name: "main", kind: .localBranch, isCurrent: true),
                    GitRef(name: "origin/main", kind: .remoteBranch),
                ],
                minutesAgo: 4
            ),
            commit("b1", "refactor: lane algoritması", parents: ["d1"], minutesAgo: 40),
            commit(
                "c1", "fix: ref rozetleri", parents: ["d1"],
                refs: [GitRef(name: "v0.7.0", kind: .tag)], minutesAgo: 90
            ),
            commit("d1", "chore: ilk commit", parents: [], minutesAgo: 3000),
        ]
    }()

    static let markdown = """
    # Lumi

    Birden çok Claude Code CLI instance'ını yöneten **desktop dashboard**.

    ## Kurulum

    1. `swift build`
    2. `swift run Lumi`

    > Terminaller arka planda yaşar; görünürlük ve odak ayrı kanallardır.

    ```swift
    let container = AppContainer()
    ```

    ---

    Ayrıntılar için `docs/design/` klasörüne bakın.
    """

    static func diff(filePath: String = "Sources/Lumi/App.swift") -> UnifiedDiff {
        UnifiedDiff(
            filePath: filePath,
            isBinary: false,
            hunks: [
                DiffHunk(
                    header: "@@ -12,7 +12,9 @@ struct App",
                    lines: [
                        DiffLine(kind: .context, oldLineNumber: 12, newLineNumber: 12, text: "## Kurulum"),
                        DiffLine(kind: .context, oldLineNumber: 13, newLineNumber: 13, text: ""),
                        DiffLine(kind: .deletion, oldLineNumber: 14, newLineNumber: nil, text: "1. `swift build`"),
                        DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 14, text: "1. `swift build -c release`"),
                        DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 15, text: "2. `swift run Lumi`"),
                        DiffLine(kind: .context, oldLineNumber: 15, newLineNumber: 16, text: ""),
                    ]
                ),
            ]
        )
    }
}

// MARK: - Store fabrikaları

public extension UsageStore {
    /// Sabit yüzdeli sahte bir servisle kurulur ve hemen yüklenir; preview
    /// `@Observable` üzerinden dolu hâli görür.
    @MainActor
    static func preview(provider: AgentProvider = .claude, percent: Int = 42) -> UsageStore {
        let store = UsageStore(
            service: PreviewUsageService(provider: provider, percent: percent)
        )
        Task { await store.loadInitialIfNeeded() }
        return store
    }
}

public extension DeepSeekBalanceStore {
    /// Dolu bir bakiyeyle kurulur (karar 75 preview'ları).
    @MainActor
    static var preview: DeepSeekBalanceStore {
        let store = DeepSeekBalanceStore(service: PreviewDeepSeekBalanceService())
        store.setEnabled(true)
        Task { await store.loadInitialIfNeeded() }
        return store
    }
}

/// Ağsız sahte bakiye (karar 75).
private struct PreviewDeepSeekBalanceService: DeepSeekBalanceServicing {
    func fetch() async throws -> DeepSeekBalance {
        DeepSeekBalance(
            isAvailable: true,
            accounts: [
                DeepSeekBalance.Account(
                    currency: "USD", total: 1.69, granted: 0, toppedUp: 1.69
                )
            ],
            fetchedAt: Date()
        )
    }
}

public extension ClaudeAccountStore {
    /// İki hesaplı, ikincisi aktif bir store (karar 56 preview'ları).
    @MainActor
    static var preview: ClaudeAccountStore {
        let store = ClaudeAccountStore(
            service: PreviewClaudeAccountService(), toasts: ToastStore()
        )
        Task { await store.load() }
        return store
    }
}

public extension RepoStore.RepoGroup {
    /// İki gruplu örnek repo listesi (dropdown preview'ı).
    static var previewGroups: [RepoStore.RepoGroup] {
        [
            RepoStore.RepoGroup(
                id: "__projects_root__",
                label: "Projects Root",
                repos: [
                    Repo(name: "lumi", path: "/Users/preview/Projects/lumi", isGitRepo: true, source: .projectsRoot),
                    Repo(name: "orca", path: "/Users/preview/Projects/orca", isGitRepo: true, source: .projectsRoot),
                    Repo(name: "scratch", path: "/Users/preview/Projects/scratch", isGitRepo: false, source: .projectsRoot),
                ]
            ),
            RepoStore.RepoGroup(
                id: "standalone",
                label: "Standalone Repos",
                repos: [
                    Repo(name: "dotfiles", path: "/Users/preview/dotfiles", isGitRepo: true, source: .standalone),
                ]
            ),
        ]
    }
}

private struct PreviewSessionStarterService: SessionStarterServicing {
    func start(prompt: String) async throws {}
}

private struct PreviewSystemService: SystemServicing {
    func runChecks(selectedProvider: AgentProvider) async -> [SystemCheckResult] { [] }
    func fixProcessPath() async {}
    func openWithDefaultApp(path: String) {}
    func openExternal(_ url: URL) throws {}
    func trash(path: String) async throws {}
    func revealInFinder(path: String) {}
    @MainActor func chooseFolder() async -> String? { nil }
}

private final class PreviewHighlighter: SyntaxHighlighting {
    func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString {
        NSAttributedString(string: code)
    }
}

@MainActor
private final class PreviewRemoteService: RemoteServicing {
    var state: RemoteConnectionState { .disconnected }
    var currentConfig: RemoteConfig { .defaults }
    func updateConfig(_ mutate: @Sendable (inout RemoteConfig) -> Void) async {}
    func regenerateToken() async {}
    func start() async {}
    func stop() {}
    func events() -> AsyncStream<RemoteEvent> { AsyncStream { _ in } }
}
#endif
