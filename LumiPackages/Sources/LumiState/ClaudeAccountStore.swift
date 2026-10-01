import Foundation
import LumiKit
import Observation

/// Claude hesapları + aktif seçim (karar 56).
///
/// Servis tek gerçek kaynaktır: her eylem güncel snapshot'ı döndürür, store
/// onu yansıtır. Aynı anda tek bir eylem koşar (`activity`) — iç içe iki
/// switch yüzeye yarım kimlik bilgisi yazardı; UI de hangi satırın meşgul
/// olduğunu bu değerden okur.
@Observable
@MainActor
public final class ClaudeAccountStore {
    /// Süren eylem. `.idle` dışında her hâlde bütün butonlar kilitlidir.
    public enum Activity: Equatable, Sendable {
        case idle
        case adding
        case reauthenticating(accountID: String)
        case removing(accountID: String)
        case switching(to: ClaudeAccountSelection)
    }

    public private(set) var accounts: [ClaudeAccount] = []
    public private(set) var selection: ClaudeAccountSelection = .systemDefault
    public private(set) var systemDefaultEmail: String?
    public private(set) var activity: Activity = .idle

    @ObservationIgnored private let service: any ClaudeAccountServicing
    @ObservationIgnored private let toasts: ToastStore
    /// Hesap değişince kullanım göstergesi başka bir hesabı gösterir —
    /// enjekte edilir, çünkü store `UsageStore`'u tanımak zorunda değil.
    @ObservationIgnored private let onAccountSwitched: @MainActor () -> Void

    public init(
        service: any ClaudeAccountServicing,
        toasts: ToastStore,
        onAccountSwitched: @escaping @MainActor () -> Void = {}
    ) {
        self.service = service
        self.toasts = toasts
        self.onAccountSwitched = onAccountSwitched
    }

    // MARK: - Türevler

    public var isBusy: Bool { activity != .idle }

    public var activeAccount: ClaudeAccount? {
        selection.accountID.flatMap { id in accounts.first { $0.id == id } }
    }

    /// Topbar/popover etiketi: aktif hesabın e-postası; sistem varsayılanında
    /// Mac'teki login'in e-postası, o da okunamazsa "System default".
    public var activeLabel: String {
        activeAccount?.email ?? systemDefaultEmail ?? Self.systemDefaultLabel
    }

    public static let systemDefaultLabel = "System default"

    public func isActive(_ selection: ClaudeAccountSelection) -> Bool {
        self.selection == selection
    }

    /// Tarayıcıda bir oturum açma akışı sürüyor mu? Ekleme ve yeniden
    /// doğrulama aynı akıştır — ikisinde de iptal sunulur.
    public var isSigningIn: Bool { activity == .adding || isReauthenticating }

    // MARK: - Eylemler

    public func load() async {
        apply(await service.accounts())
    }

    public func addAccount() async {
        await run(.adding) { [service] in try await service.addAccount() }
    }

    /// Süren login'i iptal eder (tarayıcı açıldı ama kullanıcı vazgeçti).
    public func cancelPendingLogin() async {
        guard isSigningIn else { return }
        await service.cancelPendingLogin()
    }

    public func reauthenticate(_ account: ClaudeAccount) async {
        await run(.reauthenticating(accountID: account.id)) { [service] in
            try await service.reauthenticate(accountID: account.id)
        }
    }

    public func removeAccount(_ account: ClaudeAccount) async {
        let wasActive = selection == .account(account.id)
        let succeeded = await run(.removing(accountID: account.id)) { [service] in
            try await service.removeAccount(accountID: account.id)
        }
        guard succeeded else { return }
        toasts.show(
            .info,
            title: "Account removed",
            message: wasActive
                ? "\(account.email) was removed; Claude is back on your system login."
                : "\(account.email) was removed."
        )
        if wasActive { onAccountSwitched() }
    }

    public func select(_ selection: ClaudeAccountSelection) async {
        guard selection != self.selection else { return }
        let succeeded = await run(.switching(to: selection)) { [service] in
            try await service.select(selection)
        }
        guard succeeded else { return }
        onAccountSwitched()
        toasts.show(
            .success,
            title: "Switched to \(activeLabel)",
            message: "Restart running Claude terminals before continuing old conversations."
        )
    }

    // MARK: - Ortak koridor

    private var isReauthenticating: Bool {
        if case .reauthenticating = activity { return true }
        return false
    }

    @discardableResult
    private func run(
        _ activity: Activity,
        _ operation: @escaping @MainActor () async throws -> ClaudeAccountsSnapshot
    ) async -> Bool {
        guard !isBusy else { return false }
        self.activity = activity
        defer { self.activity = .idle }
        return await toasts.reporting { [weak self] in
            let snapshot = try await operation()
            self?.apply(snapshot)
        }
    }

    private func apply(_ snapshot: ClaudeAccountsSnapshot) {
        accounts = snapshot.accounts
        selection = snapshot.selection
        systemDefaultEmail = snapshot.systemDefaultEmail
    }
}
