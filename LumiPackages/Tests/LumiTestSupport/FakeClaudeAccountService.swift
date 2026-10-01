import Foundation
import LumiKit

/// `ClaudeAccountServicing` test ikamesi (karar 56). Hesap listesini bellekte
/// tutar; `claude` binary'si ve keychain'e hiç dokunmaz.
public actor FakeClaudeAccountService: ClaudeAccountServicing {
    public private(set) var addCount = 0
    public private(set) var cancelCount = 0
    public private(set) var reauthenticated: [String] = []
    public private(set) var removed: [String] = []
    public private(set) var selections: [ClaudeAccountSelection] = []

    private var snapshot: ClaudeAccountsSnapshot
    private var error: LumiError?
    /// `addAccount` çağrısında listeye eklenecek hesap.
    private var nextAccount: ClaudeAccount?

    public init(snapshot: ClaudeAccountsSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public func seed(_ snapshot: ClaudeAccountsSnapshot) {
        self.snapshot = snapshot
    }

    public func setError(_ error: LumiError?) {
        self.error = error
    }

    public func setNextAccount(_ account: ClaudeAccount?) {
        nextAccount = account
    }

    public func accounts() async -> ClaudeAccountsSnapshot { snapshot }

    public func syncActiveSelection() async {}

    public func addAccount() async throws -> ClaudeAccountsSnapshot {
        addCount += 1
        try failIfNeeded()
        if let account = nextAccount {
            snapshot = ClaudeAccountsSnapshot(
                accounts: snapshot.accounts + [account], selection: snapshot.selection
            )
        }
        return snapshot
    }

    public func cancelPendingLogin() async {
        cancelCount += 1
    }

    public func reauthenticate(accountID: String) async throws -> ClaudeAccountsSnapshot {
        reauthenticated.append(accountID)
        try failIfNeeded()
        return snapshot
    }

    public func removeAccount(accountID: String) async throws -> ClaudeAccountsSnapshot {
        removed.append(accountID)
        try failIfNeeded()
        let remaining = snapshot.accounts.filter { $0.id != accountID }
        let selection: ClaudeAccountSelection = snapshot.selection == .account(accountID)
            ? .systemDefault : snapshot.selection
        snapshot = ClaudeAccountsSnapshot(
            accounts: remaining, selection: selection, systemDefaultEmail: snapshot.systemDefaultEmail
        )
        return snapshot
    }

    public func select(_ selection: ClaudeAccountSelection) async throws -> ClaudeAccountsSnapshot {
        selections.append(selection)
        try failIfNeeded()
        snapshot = ClaudeAccountsSnapshot(
            accounts: snapshot.accounts, selection: selection,
            systemDefaultEmail: snapshot.systemDefaultEmail
        )
        return snapshot
    }

    private func failIfNeeded() throws {
        if let error { throw error }
    }
}
