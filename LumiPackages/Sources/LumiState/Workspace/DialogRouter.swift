import Foundation
import LumiKit
import Observation

/// Close-tab guard dialogunun sunum verisi.
public struct CloseTabDialogState: Equatable, Sendable {
    public let repoPath: String
    public let repoName: String
    public let minimizedCount: Int

    public init(repoPath: String, repoName: String, minimizedCount: Int) {
        self.repoPath = repoPath
        self.repoName = repoName
        self.minimizedCount = minimizedCount
    }
}

/// Workspace silme onayının sunum verisi (karar 49).
public struct DeleteWorkspaceDialogState: Equatable, Sendable {
    public let workspace: ProjectWorkspace
    /// Silmeyle birlikte kapanacak canlı terminal sayısı.
    public let sessionCount: Int

    public init(workspace: ProjectWorkspace, sessionCount: Int) {
        self.workspace = workspace
        self.sessionCount = sessionCount
    }
}

/// Kabuğun modal/overlay durumu — TEK alan (refactor 5.2).
///
/// Önceden beş bağımsız bayrak vardı (`isRepoSelectorOpen`, `isSettingsOpen`,
/// `isOnboardingActive`, `closeTabDialog`, `quitDialogTerminalCount`); 2^5
/// durumun yalnız 6'sı geçerliydi ve "şu an bir overlay açık mı?" sorusu her
/// çağrı yerinde elle `||` listesi olarak yeniden yazılıyordu. Sum type ile
/// geçersiz durumlar TEMSİL EDİLEMEZ ve türevler yapısal olarak gelir.
public enum ActiveDialog: Equatable, Sendable {
    case none
    case repoSelector
    case sidebarProjectSelector
    case createWorkspace(projectPath: String)
    case settings
    case onboarding
    case closeTab(CloseTabDialogState)
    case deleteWorkspace(DeleteWorkspaceDialogState)
    case quit(terminalCount: Int)

    public var isPresented: Bool { self != .none }

    /// Terminal girdisini bloklaması gereken overlay'ler (Faz 6.5
    /// `OverlayDescriptor.blocksTerminalInput` bunun yerine geçecek).
    public var isInputBlockingOverlay: Bool {
        switch self {
        case .none: false
        case .repoSelector, .sidebarProjectSelector, .createWorkspace, .settings, .onboarding, .closeTab,
             .deleteWorkspace, .quit: true
        }
    }
}

/// Hangi modalın açık olduğunun tek otoritesi (refactor 5.2).
@Observable
@MainActor
public final class DialogRouter {
    public private(set) var active: ActiveDialog = .none

    /// RepoSelector grup collapse durumu — session-local, persist edilmez
    /// (collapsedGroups paritesi). Dialog kapansa da korunur.
    public var collapsedRepoGroups: Set<String> = []

    /// Quit-onay çözümü app delegate'e köprülenir (.terminateLater akışı).
    @ObservationIgnored public var onQuitResolved: ((Bool) -> Void)?

    public init() {}

    // MARK: - Türevler

    public var isInputBlockingOverlayOpen: Bool { active.isInputBlockingOverlay }

    public var closeTabDialog: CloseTabDialogState? {
        guard case .closeTab(let state) = active else { return nil }
        return state
    }

    public var deleteWorkspaceDialog: DeleteWorkspaceDialogState? {
        guard case .deleteWorkspace(let state) = active else { return nil }
        return state
    }

    public var quitDialogTerminalCount: Int? {
        guard case .quit(let count) = active else { return nil }
        return count
    }

    public func isPresenting(_ dialog: ActiveDialog) -> Bool { active == dialog }

    /// Parametresiz dialog'lar için okuma+yazma adaptörleri. Kapatma YALNIZ o
    /// dialog açıkken etkilidir (`dismiss(_:)`) — bayrak set'i başka bir modalı
    /// kazara kapatmaz.
    public var isRepoSelectorOpen: Bool {
        get { isPresenting(.repoSelector) }
        set { setPresented(.repoSelector, newValue) }
    }

    public var isSettingsOpen: Bool {
        get { isPresenting(.settings) }
        set { setPresented(.settings, newValue) }
    }

    public var isOnboardingActive: Bool {
        get { isPresenting(.onboarding) }
        set { setPresented(.onboarding, newValue) }
    }

    public func setPresented(_ dialog: ActiveDialog, _ presented: Bool) {
        if presented {
            present(dialog)
        } else {
            dismiss(dialog)
        }
    }

    // MARK: - Sunum

    public func present(_ dialog: ActiveDialog) {
        active = dialog
    }

    public func dismiss() {
        active = .none
    }

    /// Yalnız BELİRTİLEN dialog açıksa kapatır — bayrak adaptörlerinin
    /// (`isSettingsOpen = false`) başka bir modalı yanlışlıkla kapatmasını
    /// engeller.
    public func dismiss(_ dialog: ActiveDialog) {
        guard active == dialog else { return }
        active = .none
    }

    // MARK: - Quit akışı

    public func presentQuitDialog(terminalCount: Int) {
        active = .quit(terminalCount: terminalCount)
    }

    public func resolveQuit(_ shouldQuit: Bool) {
        if case .quit = active { active = .none }
        onQuitResolved?(shouldQuit)
    }
}
