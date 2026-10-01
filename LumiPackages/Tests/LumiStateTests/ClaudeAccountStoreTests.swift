import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 56 — hesap store'unun eylem koridoru.
@MainActor
final class ClaudeAccountStoreTests: XCTestCase {
    private var service: FakeClaudeAccountService!
    private var toasts: ToastStore!
    private var switchCount = 0

    private static let personal = ClaudeAccount(
        id: "personal", email: "dev@example.com",
        createdAt: .distantPast, updatedAt: .distantPast, lastAuthenticatedAt: .distantPast
    )
    private static let work = ClaudeAccount(
        id: "work", email: "dev@company.com",
        createdAt: .distantPast, updatedAt: .distantPast, lastAuthenticatedAt: .distantPast
    )

    override func setUp() async throws {
        service = FakeClaudeAccountService(
            snapshot: ClaudeAccountsSnapshot(
                accounts: [Self.personal, Self.work], selection: .systemDefault
            )
        )
        toasts = ToastStore(autoDismissAfter: 60)
        switchCount = 0
    }

    private func makeStore() -> ClaudeAccountStore {
        ClaudeAccountStore(
            service: service, toasts: toasts,
            onAccountSwitched: { [weak self] in self?.switchCount += 1 }
        )
    }

    func testLoadReflectsTheServiceSnapshot() async {
        let store = makeStore()
        await store.load()

        XCTAssertEqual(store.accounts.map(\.id), ["personal", "work"])
        XCTAssertEqual(store.selection, .systemDefault)
        XCTAssertEqual(store.activeLabel, "System default")
        XCTAssertFalse(store.isBusy)
    }

    func testSystemDefaultLabelShowsTheMacLoginEmailWhenKnown() async {
        await service.seed(ClaudeAccountsSnapshot(
            accounts: [Self.personal], selection: .systemDefault,
            systemDefaultEmail: "me@home.com"
        ))
        let store = makeStore()
        await store.load()

        XCTAssertEqual(store.systemDefaultEmail, "me@home.com")
        XCTAssertEqual(store.activeLabel, "me@home.com")

        await store.select(.account("personal"))
        XCTAssertEqual(store.activeLabel, Self.personal.email)
    }

    func testSelectingAnAccountUpdatesTheLabelAndRefreshesUsage() async {
        let store = makeStore()
        await store.load()

        await store.select(.account("work"))

        XCTAssertEqual(store.selection, .account("work"))
        XCTAssertEqual(store.activeLabel, "dev@company.com")
        XCTAssertEqual(switchCount, 1, "gösterge yeni hesabın kotasını çekmeli")
        let selections = await service.selections
        XCTAssertEqual(selections, [.account("work")])
    }

    /// Zaten aktif olan satıra tıklamak servise gitmez (gereksiz materialize).
    func testSelectingTheActiveSelectionIsANoOp() async {
        let store = makeStore()
        await store.load()

        await store.select(.systemDefault)

        let selections = await service.selections
        XCTAssertEqual(selections, [])
        XCTAssertEqual(switchCount, 0)
    }

    func testFailedSwitchKeepsThePreviousSelectionAndShowsTheError() async {
        let store = makeStore()
        await store.load()
        await service.setError(.claudeAccountFailed(operation: "switch", detail: "keychain locked"))

        await store.select(.account("work"))

        XCTAssertEqual(store.selection, .systemDefault)
        XCTAssertEqual(switchCount, 0, "başarısız switch'te gösterge tazelenmez")
        XCTAssertEqual(toasts.toasts.count, 1)
        XCTAssertFalse(store.isBusy, "hata sonrası butonlar yeniden açılmalı")
    }

    func testAddAccountAppendsTheNewRow() async {
        let store = makeStore()
        await store.load()
        let added = ClaudeAccount(
            id: "new", email: "new@example.com",
            createdAt: .distantPast, updatedAt: .distantPast, lastAuthenticatedAt: .distantPast
        )
        await service.setNextAccount(added)

        await store.addAccount()

        XCTAssertEqual(store.accounts.map(\.id), ["personal", "work", "new"])
        XCTAssertEqual(store.selection, .systemDefault, "ekleme seçimi değiştirmez")
    }

    func testRemovingTheActiveAccountFallsBackToSystemDefault() async {
        let store = makeStore()
        await store.load()
        await store.select(.account("work"))

        await store.removeAccount(Self.work)

        XCTAssertEqual(store.accounts.map(\.id), ["personal"])
        XCTAssertEqual(store.selection, .systemDefault)
        XCTAssertEqual(switchCount, 2, "silme de göstergeyi tazeler")
    }

    func testCancelOnlyReachesTheServiceWhileALoginIsRunning() async {
        let store = makeStore()
        await store.cancelPendingLogin()
        let cancels = await service.cancelCount
        XCTAssertEqual(cancels, 0, "login yokken iptal anlamsız")
    }

    /// Bir eylem sürerken ikincisi başlamaz: iç içe iki switch yüzeye yarım
    /// kimlik bilgisi yazardı.
    func testASecondActionIsRejectedWhileOneIsRunning() async {
        let store = makeStore()
        await store.load()
        let first = Task { await store.select(.account("work")) }
        await store.select(.account("personal"))
        await first.value

        let selections = await service.selections
        XCTAssertEqual(selections.count, 1)
    }
}
