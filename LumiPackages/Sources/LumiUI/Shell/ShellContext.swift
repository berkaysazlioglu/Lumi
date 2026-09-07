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

    public init(
        chooseFolder: @escaping @MainActor () async -> String?,
        reveal: @escaping @MainActor (String, String) -> Void,
        trash: @escaping @MainActor (String, String) -> Void
    ) {
        self.chooseFolder = chooseFolder
        self.reveal = reveal
        self.trash = trash
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
    public let agentHistory: AgentHistoryStore
    public let git: GitStore
    /// Plastic SCM panel store'u (karar 46).
    public let plastic: PlasticStore
    /// Commit mesajı üretimi (karar 47) — Git ve Plastic composer'ları paylaşır.
    public let commitAssistant: CommitMessageAssistant
    public let fileViewer: FileViewerStore
    public let settings: SettingsStore
    public let sessionSchedule: SessionScheduleStore
    public let promptQueue: PromptQueueStore
    public let toasts: ToastStore
    public let onboarding: OnboardingStore
    /// Sağlayıcı başına kullanım store'u (karar 32).
    public let usage: [AgentProvider: UsageStore]
    /// Alt bar store'ları (karar 43).
    public let computerAwake: ComputerAwakeStore
    public let resourceUsage: ResourceUsageStore

    // MARK: - Köprüler

    @ObservationIgnored public let viewProvider: any TerminalViewProviding
    @ObservationIgnored public let highlighter: any SyntaxHighlighting
    @ObservationIgnored public let actions: ShellActions

    public init(
        navigation: NavigationStore,
        layout: LayoutStore,
        dialogs: DialogRouter,
        terminals: TerminalListStore,
        repos: RepoStore,
        git: GitStore,
        plastic: PlasticStore,
        commitAssistant: CommitMessageAssistant,
        agentHistory: AgentHistoryStore,
        fileViewer: FileViewerStore,
        settings: SettingsStore,
        sessionSchedule: SessionScheduleStore,
        promptQueue: PromptQueueStore,
        toasts: ToastStore,
        onboarding: OnboardingStore,
        usage: [AgentProvider: UsageStore],
        computerAwake: ComputerAwakeStore,
        resourceUsage: ResourceUsageStore,
        viewProvider: any TerminalViewProviding,
        highlighter: any SyntaxHighlighting,
        actions: ShellActions
    ) {
        self.navigation = navigation
        self.layout = layout
        self.dialogs = dialogs
        self.terminals = terminals
        self.repos = repos
        self.git = git
        self.plastic = plastic
        self.commitAssistant = commitAssistant
        self.agentHistory = agentHistory
        self.fileViewer = fileViewer
        self.settings = settings
        self.sessionSchedule = sessionSchedule
        self.promptQueue = promptQueue
        self.toasts = toasts
        self.onboarding = onboarding
        self.usage = usage
        self.computerAwake = computerAwake
        self.resourceUsage = resourceUsage
        self.viewProvider = viewProvider
        self.highlighter = highlighter
        self.actions = actions
    }

    // MARK: - Türevler

    /// `.repo` route'unun projeksiyonu — panel öğelerinin `isAvailable` kapısı.
    public var activeRepoPath: String? { navigation.activeRepoPath }

    public var isFocusMode: Bool { layout.isFocusMode }

    // MARK: - Koordinasyon intent'leri (birden fazla store'a dokunanlar)

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
        navigation.closeTab(dialog.repoPath)
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

    public func presentDiff(_ filePath: String) {
        guard let repoPath = activeRepoPath else { return }
        Task { await fileViewer.presentDiff(repoPath: repoPath, filePath: filePath) }
    }

    public func presentCommit(_ commit: GitCommit) {
        guard let repoPath = activeRepoPath else { return }
        Task { await fileViewer.presentCommit(repoPath: repoPath, commit: commit) }
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
