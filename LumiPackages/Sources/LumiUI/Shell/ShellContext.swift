import LumiKit
import LumiState
import Observation
import SwiftUI

/// Kabuğun sistem etkileşimleri. View'lar servisleri asla görmez
/// (design/00 §3): dosya/panel dışı her yan etki composition root'un bağladığı
/// bu closure'lardan geçer.
public struct ShellActions {
    /// Klasör seçici (NSOpenPanel) — Settings ve onboarding.
    public let chooseFolder: @MainActor () async -> String?
    /// (repoPath, göreli yol) → Finder'da göster.
    public let reveal: @MainActor (String, String) -> Void
    /// (repoPath, göreli yol) → çöp kutusuna taşı.
    public let trash: @MainActor (String, String) -> Void
    /// Mutlak proje/workspace yolunu Finder'da göster (karar 51).
    public let revealPath: @MainActor (String) -> Void
    /// http/https linkini sistemdeki varsayılan tarayıcıda aç (karar 57).
    public let openURL: @MainActor (URL) -> Void
    /// Dosyayı sistemin varsayılan uygulamasında aç (karar 57).
    public let openPath: @MainActor (String) -> Void

    public init(
        chooseFolder: @escaping @MainActor () async -> String?,
        reveal: @escaping @MainActor (String, String) -> Void,
        trash: @escaping @MainActor (String, String) -> Void,
        revealPath: @escaping @MainActor (String) -> Void = { _ in },
        openURL: @escaping @MainActor (URL) -> Void = { _ in },
        openPath: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.chooseFolder = chooseFolder
        self.reveal = reveal
        self.trash = trash
        self.revealPath = revealPath
        self.openURL = openURL
        self.openPath = openPath
    }
}

/// Kabuğun TEK bağlamı (Faz 6.1, K33).
///
/// Registry'den dinamik inşa edilen panel öğeleri / route'lar / overlay'ler
/// `init()` ile kurulur ve bağlamı Environment'tan okur — bu yüzden prop
/// drilling'in (RootView → HeaderBar → RepoTabStrip, `usageStores`'un iki
/// yoldan taşınması) yerine tek bir enjeksiyon noktası vardır:
/// `.environment(\.shell, context)`.
///
/// **Facade yok:** `WorkspaceStore` Faz 6.1'de kaldırıldı; kabuk alt store'ları
/// (`navigation` / `layout` / `dialogs`) doğrudan sunar. Burada yalnız BİRDEN
/// FAZLA store'a dokunan koordinasyon intent'leri yaşar (close-tab guard'ı,
/// FileViewer sunumları) — tek store'a giden her şey doğrudan çağrılır.
@Observable
@MainActor
public final class ShellContext {
    // MARK: - Store'lar

    public let navigation: NavigationStore
    public let layout: LayoutStore
    public let dialogs: DialogRouter
    public let terminals: TerminalListStore
    public let repos: RepoStore
    public let workspaces: ProjectWorkspaceStore
    /// Proje hızlı komutları (karar 92).
    public let quickCommands: QuickCommandStore
    /// Proje favori dosyaları (karar 107).
    public let favoriteFiles: FavoriteFileStore
    public let agentHistory: AgentHistoryStore
    public let git: GitStore
    /// Plastic SCM panel store'u (karar 46).
    public let plastic: PlasticStore
    /// Commit mesajı üretimi (karar 47) — Git ve Plastic composer'ları paylaşır.
    public let commitAssistant: CommitMessageAssistant
    public let fileViewer: FileViewerStore
    public let settings: SettingsStore
    public let remote: RemoteStore
    public let sessionSchedule: SessionScheduleStore
    public let promptQueue: PromptQueueStore
    /// Serbest terminallerin konumu (karar 108).
    public let looseTerminals: LooseTerminalStore
    public let toasts: ToastStore
    public let onboarding: OnboardingStore
    /// Sağlayıcı başına kullanım store'u (karar 32).
    public let usage: [AgentProvider: UsageStore]
    /// DeepSeek env kurulumu (karar 54) — Settings ▸ Agent + New DeepSeek.
    public let deepSeek: DeepSeekStore
    /// DeepSeek bakiye göstergesi (karar 75).
    public let deepSeekBalance: DeepSeekBalanceStore
    /// Claude hesapları (karar 56) — Settings ▸ Accounts + usage popover'ı.
    public let claudeAccounts: ClaudeAccountStore
    /// Codex isolated-home account selection.
    public let codexAccounts: CodexAccountStore
    /// Terminal link eylemleri (karar 57) — tık noktasındaki popover.
    public let terminalLinks: TerminalLinkActionStore
    /// Alt bar store'ları (karar 43).
    public let computerAwake: ComputerAwakeStore
    public let resourceUsage: ResourceUsageStore
    /// Settings ▸ About'un sürüm kontrolü (karar 102).
    public let appUpdate: AppUpdateStore

    // MARK: - Köprüler

    @ObservationIgnored public let viewProvider: any TerminalViewProviding
    @ObservationIgnored public let highlighter: any SyntaxHighlighting
    @ObservationIgnored public let markdownParser: any MarkdownParsing
    @ObservationIgnored public let actions: ShellActions

    public init(
        navigation: NavigationStore,
        layout: LayoutStore,
        dialogs: DialogRouter,
        terminals: TerminalListStore,
        repos: RepoStore,
        workspaces: ProjectWorkspaceStore,
        quickCommands: QuickCommandStore,
        favoriteFiles: FavoriteFileStore,
        git: GitStore,
        plastic: PlasticStore,
        commitAssistant: CommitMessageAssistant,
        agentHistory: AgentHistoryStore,
        fileViewer: FileViewerStore,
        settings: SettingsStore,
        remote: RemoteStore,
        sessionSchedule: SessionScheduleStore,
        promptQueue: PromptQueueStore,
        looseTerminals: LooseTerminalStore,
        toasts: ToastStore,
        onboarding: OnboardingStore,
        usage: [AgentProvider: UsageStore],
        deepSeek: DeepSeekStore,
        deepSeekBalance: DeepSeekBalanceStore,
        claudeAccounts: ClaudeAccountStore,
        codexAccounts: CodexAccountStore,
        terminalLinks: TerminalLinkActionStore,
        computerAwake: ComputerAwakeStore,
        resourceUsage: ResourceUsageStore,
        appUpdate: AppUpdateStore,
        viewProvider: any TerminalViewProviding,
        highlighter: any SyntaxHighlighting,
        markdownParser: any MarkdownParsing,
        actions: ShellActions
    ) {
        self.navigation = navigation
        self.layout = layout
        self.dialogs = dialogs
        self.terminals = terminals
        self.repos = repos
        self.workspaces = workspaces
        self.quickCommands = quickCommands
        self.favoriteFiles = favoriteFiles
        self.git = git
        self.plastic = plastic
        self.commitAssistant = commitAssistant
        self.agentHistory = agentHistory
        self.fileViewer = fileViewer
        self.settings = settings
        self.remote = remote
        self.sessionSchedule = sessionSchedule
        self.promptQueue = promptQueue
        self.looseTerminals = looseTerminals
        self.toasts = toasts
        self.onboarding = onboarding
        self.usage = usage
        self.deepSeek = deepSeek
        self.deepSeekBalance = deepSeekBalance
        self.claudeAccounts = claudeAccounts
        self.codexAccounts = codexAccounts
        self.terminalLinks = terminalLinks
        self.computerAwake = computerAwake
        self.resourceUsage = resourceUsage
        self.appUpdate = appUpdate
        self.viewProvider = viewProvider
        self.highlighter = highlighter
        self.markdownParser = markdownParser
        self.actions = actions
    }

    // MARK: - Türevler

    /// `.repo` route'unun projeksiyonu — panel öğelerinin `isAvailable` kapısı.
    public var activeRepoPath: String? { navigation.activeRepoPath }

    /// Karar 103: orta alan bir terminal yüzeyiyse kapsamı — repo route'u ya
    /// da All Terminals. Grid/Edit gibi yüzey kontrollerinin kapısı; repo'ya
    /// bağlı eylemler (spawn, hızlı komutlar) `activeRepoPath`'te kalır.
    public var activeTerminalScope: TerminalScope? { navigation.activeRoute.terminalScope }

    /// Yüzeyden terminal açmanın TEK intent'i (top bar, boş durum, focus bar,
    /// dropdown). Repo yüzeyi kendi checkout'unda açar; All Terminals serbest
    /// terminali geçerli konumda açar (karar 108) — konum silinmişse store
    /// uyarır ve terminal açılmaz.
    public func spawnTerminal(in scope: TerminalScope, command: String?, task: String? = nil) {
        let directory: String
        switch scope {
        case .repo(let repoPath):
            directory = repoPath
        case .all:
            guard let location = looseTerminals.locationForSpawn() else { return }
            directory = location
        }
        terminals.spawn(in: directory, command: command, task: task)
    }

    /// Checkout'un kullanıcıya görünen adı: proje kökü için proje adı,
    /// yönetilen workspace için `proje / workspace` (Projects panelindeki
    /// hiyerarşinin tek satırlık hâli).
    public func checkoutLabel(for repoPath: String) -> String {
        if let workspace = workspaces.records.first(where: { $0.path == repoPath }) {
            return "\(projectName(at: workspace.projectPath)) / \(workspace.name)"
        }
        if let repo = repos.repo(at: repoPath) { return repo.name }
        // Karar 108: serbest terminalin "checkout"u bir proje değil, dizindir —
        // klasör adı (`Desktop`) yerine kısa yol (`~/Desktop`).
        if navigation.isLooseTerminalPath(repoPath) {
            return LooseTerminalPath.displayLabel(repoPath)
        }
        return projectName(at: repoPath)
    }

    /// Karar 108: Projects ▸ `Other` grubu — serbest terminaller dizinlerine
    /// göre, etiket sırasıyla. Grup içi sıra panelin ajan sıralamasıdır
    /// (`AgentRow.Model.sorted`), burada terminal listesinin sırası korunur.
    public var looseTerminalGroups: [LooseTerminalGroup] {
        let loose = terminals.terminals.filter { navigation.isLooseTerminalPath($0.repoPath) }
        let paths = loose.reduce(into: [String]()) { paths, meta in
            if !paths.contains(meta.repoPath) { paths.append(meta.repoPath) }
        }
        return paths
            .map { path in
                LooseTerminalGroup(
                    path: path,
                    label: LooseTerminalPath.displayLabel(path),
                    terminals: loose.filter { $0.repoPath == path }
                )
            }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private func projectName(at path: String) -> String {
        repos.repo(at: path)?.name ?? (path as NSString).lastPathComponent
    }

    public var isFocusMode: Bool { layout.isFocusMode }

    // MARK: - Koordinasyon intent'leri (birden fazla store'a dokunanlar)

    public func startWorkspaceCreation() {
        guard workspaces.startCreation(projects: repos.repos) else { return }
        if case .createWorkspace = dialogs.active { dialogs.dismiss() }
    }

    public func openCreatedWorkspace(_ workspace: ProjectWorkspace, agent: WorkspaceAgent) {
        if case .createWorkspace = dialogs.active { dialogs.dismiss() }
        navigation.openTab(workspace.path)
        if agent != .none {
            terminals.spawn(in: workspace.path, command: agent.command, task: workspace.name)
        }
    }

    /// Karar 92: hızlı komutu checkout'ta yeni bir terminalde çalıştırır —
    /// script checkout'a göre çözülüp dosyaya yazılır, checkout sekmesi açılır
    /// ve terminale `sh <dosya>` girilir. Terminal komut bitince açık kalır.
    public func runQuickCommand(_ command: ProjectQuickCommand, context: QuickCommandContext) async {
        guard let line = await quickCommands.prepareRun(command, context: context) else { return }
        navigation.openTab(context.path)
        terminals.spawn(in: context.path, command: line, task: command.name)
    }

    /// Karar 93: `Start App` terminal açmadan, Lumi'den kopuk başlar; çıktı
    /// log dosyasına gider ve yolu bilgi toast'ında söylenir.
    public func startApp(_ command: ProjectQuickCommand, context: QuickCommandContext) async {
        guard let logPath = await quickCommands.launchInBackground(command, context: context) else { return }
        toasts.show(.info, title: "Starting \(context.name)", message: "Output: \(logPath)")
    }

    public func addSidebarProject(_ project: Repo) async {
        if await workspaces.addProject(project) {
            dialogs.dismiss(.sidebarProjectSelector)
        }
    }

    /// ⇧⌘W (karar 66): aktif checkout'un PROJESİNİ Projects'ten kaldırır.
    ///
    /// ⌘W'ye değil ayrı bir korda bağlıdır — kaldırma kalıcı kullanıcı verisine
    /// dokunur ve projenin TÜM checkout'larını kapatır; ⌘W ise refleks bir tuş.
    public func requestCloseActiveProject() {
        guard let checkout = activeRepoPath,
              let projectPath = navigation.projectPath(containing: checkout),
              let project = repos.repo(at: projectPath)
        else { return }
        requestRemoveProject(project)
    }

    /// Kaldırmanın TEK kapısı: sağ tık menüsü de ⇧⌘W de buradan geçer.
    ///
    /// Minimize terminal varsa önce onay sorulur. Karar 65'te kaldırma açık
    /// checkout'ları kapatmaya başlamıştı ama `closeTab`'ı doğrudan çağırıp
    /// `requestCloseTab` guard'ını ATLIYORDU — görünmeyen bir terminal
    /// sessizce ölüyordu. Guard artık projenin tüm checkout'ları üzerinden
    /// toplanır.
    public func requestRemoveProject(_ project: Repo) {
        let minimized = projectCheckouts(of: project.path)
            .reduce(0) { $0 + terminals.minimizedTerminals(in: $1).count }
        guard minimized > 0 else {
            Task { await removeSidebarProject(project) }
            return
        }
        dialogs.present(.closeTab(CloseTabDialogState(
            repoPath: project.path,
            repoName: project.name,
            minimizedCount: minimized,
            isProject: true
        )))
    }

    private func projectCheckouts(of projectPath: String) -> [String] {
        [projectPath] + workspaces.workspaces(for: projectPath).map(\.path)
    }

    /// Projects'ten çıkarma (karar 65): açık checkout'ları da KAPATIR.
    ///
    /// Projects tek gezinme evreni olduğu için, listeden çıkan bir projenin
    /// açık kalan checkout'una ulaşmanın yolu kalmazdı — ne panelde görünür,
    /// ne indeksli kısayolda, ne ⌘O'da. Açık terminalleri de serbest bırakır.
    public func removeSidebarProject(_ project: Repo) async {
        for checkout in [project.path] + workspaces.workspaces(for: project.path).map(\.path)
        where navigation.openTabs.contains(checkout) {
            navigation.closeTab(checkout)
        }
        await workspaces.removeProject(project)
    }

    /// ⌘O'nun hedefi (karar 65): projeye GİT.
    ///
    /// Projects listesinde yoksa önce eklenir — "açtığın şeyi Projects'te
    /// görürsün" kuralı buradan gelir; eskiden ⌘O görünmeyen bir tab
    /// yaratıyordu ve o repo'ya bir daha ⌘O ile dönülemiyordu (seçici açık
    /// tab'ları dışlıyordu). Zaten ekliyse yalnız geçilir.
    ///
    /// Açılan checkout, o projede en son kullanılandır (`checkoutToOpen`);
    /// hiç kullanılmamışsa projenin kendi kökü.
    public func goToProject(_ project: Repo) async {
        if !workspaces.sidebarProjectPaths.contains(project.path) {
            _ = await workspaces.addProject(project)
        }
        navigation.openTab(navigation.checkoutToOpen(in: project.path))
    }

    // MARK: - Projects paneli ajan satırları ve silme (karar 51)

    /// Sidebar ajan satırı: terminalin sekmesi açık değilse açılır, sonra
    /// minimize edilmişse geri getirilip odaklanır. Checkout zaten maximize
    /// modundaysa seçim aynı solo yüzeyde terminal değiştirir; Projects ve
    /// maximize altındaki switcher böylece aynı davranışı taşır.
    ///
    /// Karar 108: serbest terminal repo tab'ı açmaz, All Terminals'ta öne gelir
    /// (`NavigationStore.openTerminalSurface`).
    public func focusAgent(_ meta: TerminalMeta) {
        navigation.openTerminalSurface(for: meta.repoPath)
        guard let scope = navigation.activeRoute.terminalScope else { return }
        let shouldSwitchMaximizedTerminal = layout.maximizedTerminal(in: scope) != nil
        terminals.restoreAndFocus(meta.id)
        if shouldSwitchMaximizedTerminal {
            layout.maximize(meta.id, in: scope)
        }
    }

    /// Karar 97: Edit modunu aç/kapa. Çıkışta klavye odağı (Edit modunda grid'e
    /// alınmıştı) bu repo'nun son aktif terminaline geri verilir — global aktif
    /// terminal başka repo'da olabilir.
    public func toggleArrangingTerminals(in repoPath: String) {
        toggleArrangingTerminals(in: .repo(repoPath))
    }

    /// Kapsamlı hâli (karar 103): All Terminals'ta çıkış odağı o yüzeyin son
    /// aktif kartına döner.
    public func toggleArrangingTerminals(in scope: TerminalScope) {
        layout.toggleArranging(in: scope)
        guard !layout.isArranging(in: scope),
              let id = terminals.lastActiveVisible(in: scope) else { return }
        terminals.focus(id)
    }

    /// Silme onayı: canlı oturum sayısı dialogda gösterilir; store'un önceki
    /// hata/force durumu sıfırlanır.
    public func requestDeleteWorkspace(_ workspace: ProjectWorkspace) {
        workspaces.beginDeleteFlow()
        dialogs.present(.deleteWorkspace(DeleteWorkspaceDialogState(
            workspace: workspace, sessionCount: terminals.terminals(in: workspace.path).count
        )))
    }

    /// Onay: önce sekme kapanır (terminaller ölür, cache'ler boşalır), sonra
    /// SCM/klasör/kayıt silinir. Hata dialogu açık bırakır ve kullanıcı
    /// ikinci denemede `Force Delete` görebilir.
    public func confirmDeleteWorkspace(force: Bool) async {
        guard let dialog = dialogs.deleteWorkspaceDialog else { return }
        let path = dialog.workspace.path
        // closeTab terminalleri zaten öldürür; sekme yoksa yalnız terminaller.
        if navigation.openTabs.contains(path) { navigation.closeTab(path) } else { terminals.closeAll(in: path) }
        if await workspaces.deleteWorkspace(dialog.workspace, force: force) {
            dialogs.dismiss(.deleteWorkspace(dialog))
        }
    }

    public func cancelDeleteWorkspace() {
        if case .deleteWorkspace = dialogs.active { dialogs.dismiss() }
    }

    // MARK: - Agent History oturum silme (karar 53)

    public func requestDeleteAgentSession(_ entry: AgentHistoryEntry, projectPath: String) {
        dialogs.present(.deleteAgentSession(DeleteAgentSessionDialogState(entry: entry, projectPath: projectPath)))
    }

    public func confirmDeleteAgentSession() async {
        guard let dialog = dialogs.deleteAgentSessionDialog else { return }
        if await agentHistory.deleteSession(dialog.entry, projectPath: dialog.projectPath) {
            dialogs.dismiss(.deleteAgentSession(dialog))
        }
    }

    public func cancelDeleteAgentSession() {
        if case .deleteAgentSession = dialogs.active { dialogs.dismiss() }
    }

    /// Eksik (diskte olmayan) workspace kaydını listeden düşürür.
    public func forgetWorkspace(_ workspace: ProjectWorkspace) async {
        if navigation.openTabs.contains(workspace.path) { navigation.closeTab(workspace.path) }
        await workspaces.forgetWorkspace(workspace)
    }

    /// Close-tab guard'ı: minimize edilmiş terminali olan tab dialog'suz
    /// kapanmaz (navigation sorar, dialogs sunar).
    public func requestCloseTab(_ repoPath: String, repoName: String) {
        guard let minimizedCount = navigation.requestCloseTab(repoPath) else { return }
        dialogs.present(.closeTab(CloseTabDialogState(
            repoPath: repoPath,
            repoName: repoName,
            minimizedCount: minimizedCount
        )))
    }

    public func confirmCloseTab() {
        guard let dialog = dialogs.closeTabDialog else { return }
        dialogs.dismiss()
        guard dialog.isProject else {
            navigation.closeTab(dialog.repoPath)
            return
        }
        guard let project = repos.repo(at: dialog.repoPath) else { return }
        Task { await removeSidebarProject(project) }
    }

    public func cancelCloseTab() {
        guard dialogs.closeTabDialog != nil else { return }
        dialogs.dismiss()
    }

    /// FileViewer sunumları aktif repo bağlamında akar (panel öğeleri artık
    /// parent closure'ı taşımaz).
    public func presentFile(_ filePath: String) {
        guard let repoPath = activeRepoPath else { return }
        Task { await fileViewer.presentView(repoPath: repoPath, filePath: filePath) }
    }

    /// Karar 107: favori dosyayı checkout'ta Lumi viewer'ında açar ya da
    /// Finder'da gösterir. Dosya tık anında yeniden doğrulanır — menü açıkken
    /// silinen dosya boş viewer ya da sessiz Finder yerine uyarı verir.
    public func openFavoriteFile(_ relativePath: String, in checkoutPath: String, revealInFinder: Bool) {
        guard favoriteFiles.fileExists(relativePath, in: checkoutPath) else {
            toasts.show(.error, title: "File not found", message: "\(relativePath) was moved or deleted.")
            return
        }
        if revealInFinder {
            actions.revealPath(FavoriteFilePath.absolute(relativePath, in: checkoutPath))
        } else {
            Task { await fileViewer.presentView(repoPath: checkoutPath, filePath: relativePath) }
        }
    }

    public func presentDiff(_ filePath: String) {
        guard let repoPath = activeRepoPath else { return }
        Task { await fileViewer.presentDiff(repoPath: repoPath, filePath: filePath) }
    }

    public func presentCommit(_ commit: GitCommit, file: String? = nil) {
        guard let repoPath = activeRepoPath else { return }
        Task { await fileViewer.presentCommit(repoPath: repoPath, commit: commit, initialFile: file) }
    }

    /// Karar 100: FileViewer seçiminin referansını ajan terminalinin prompt'una
    /// yapıştırır (göndermez), viewer'ı kapatır ve terminale odaklanır —
    /// kullanıcı sorusunu doğrudan yazmaya devam eder.
    public func mentionSelection(in target: TerminalMeta) {
        guard let reference = fileViewer.mentionReference,
              terminals.paste(reference, into: target.id) else { return }
        fileViewer.close()
        focusAgent(target)
    }

    /// Karar 47: seçili değişikliklerden Claude ile mesaj üret ve alana yaz.
    /// Kullanıcı bu arada yazmaya başladıysa yanıt onu EZMEZ.
    public func generateGitCommitMessage(_ repoPath: String) async {
        let draftBefore = git.commitMessage(for: repoPath)
        let request = await git.commitMessageRequest(repoPath)
        guard let message = await commitAssistant.generate(repoPath, request: request) else { return }
        if git.commitMessage(for: repoPath) == draftBefore { git.setCommitMessage(message, for: repoPath) }
    }

    public func generatePlasticCheckinMessage(_ repoPath: String) async {
        let draftBefore = plastic.checkinMessage(for: repoPath)
        let request = await plastic.checkinMessageRequest(repoPath)
        guard let message = await commitAssistant.generate(repoPath, request: request) else { return }
        if plastic.checkinMessage(for: repoPath) == draftBefore { plastic.setCheckinMessage(message, for: repoPath) }
    }

    // MARK: - Terminal link eylemleri (karar 57)

    /// Store yalnız niyeti üretir; sekme/FileViewer/Finder burada işletilir.
    public func performTerminalLinkIntent(_ intent: TerminalLinkIntent) {
        switch intent {
        case .openURL(let url):
            actions.openURL(url)
        case .switchWorkspace(let path):
            navigation.openTab(path)
        case .openFile(let repoPath, let filePath):
            Task { await fileViewer.presentView(repoPath: repoPath, filePath: filePath) }
        case .openWithDefaultApp(let path):
            actions.openPath(path)
        case .revealInFinder(let path):
            actions.revealPath(path)
        }
    }

    public func reveal(_ relativePath: String) {
        guard let repoPath = activeRepoPath else { return }
        actions.reveal(repoPath, relativePath)
    }

    public func trash(_ relativePath: String) {
        guard let repoPath = activeRepoPath else { return }
        actions.trash(repoPath, relativePath)
    }
}

// MARK: - Environment

private struct ShellContextKey: EnvironmentKey {
    static let defaultValue: ShellContext? = nil
}

public extension EnvironmentValues {
    /// Kabuğun tek Environment girdisi (Faz 6.1).
    var shell: ShellContext? {
        get { self[ShellContextKey.self] }
        set { self[ShellContextKey.self] = newValue }
    }
}

/// `@Environment(\.shell)` sarmalayıcısı: kabuk içindeki her view bağlamın
/// KURULU olduğunu varsayabilsin diye opsiyonelliği tek yerde açar.
@propertyWrapper
struct Shell: DynamicProperty {
    @Environment(\.shell) private var context

    var wrappedValue: ShellContext {
        guard let context else {
            preconditionFailure("ShellContext Environment'a konmadı (RootViewFactory kurar)")
        }
        return context
    }
}
