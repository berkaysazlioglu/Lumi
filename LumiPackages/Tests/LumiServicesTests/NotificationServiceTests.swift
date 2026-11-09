import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiServices

/// Teslim kuralları (karar 145): ayar kapısı, odaktaki terminal, pencere
/// odağı (toast ↔ OS bildirimi), checkout başına bekleme süresi.
@MainActor
final class NotificationServiceTests: XCTestCase {
    private var presenter: FakeNotificationPresenter!
    private var clock = Date(timeIntervalSince1970: 1_000)
    private var service: NotificationService!
    private var attentions: [AgentNotification] = []
    private var bridge: Task<Void, Never>?

    override func setUp() async throws {
        presenter = FakeNotificationPresenter()
        service = NotificationService(presenter: presenter, now: { [unowned self] in self.clock })
        service.setWindowFocused(false)
        attentions = []
        let stream = service.events()
        bridge = Task { @MainActor [weak self] in
            for await event in stream {
                if case .attention(let notification) = event { self?.attentions.append(notification) }
            }
        }
        await Task.yield()
    }

    override func tearDown() async throws {
        bridge?.cancel()
    }

    private func notification(
        _ kind: AgentNotification.Kind = .finished,
        id: TerminalID = TerminalID(),
        focused: Bool = false,
        group: String = "/repo"
    ) -> AgentNotification {
        AgentNotification(
            terminalID: id, kind: kind, title: "Fix login", subtitle: "lumi · Claude finished",
            body: "Done.", isTerminalFocused: focused, groupKey: group
        )
    }

    private func drain() async {
        for _ in 0..<5 { await Task.yield() }
    }

    func testBackgroundWindowPresentsOSNotificationWithContentAndSound() async {
        let id = TerminalID()
        service.deliver(notification(id: id))
        await drain()

        XCTAssertEqual(presenter.presented, [
            .init(id: id.description, title: "Fix login", subtitle: "lumi · Claude finished", body: "Done.", sound: true),
        ])
        XCTAssertEqual(attentions.count, 1, "toast da gider — kullanıcı döndüğünde görür")
    }

    func testFocusedWindowShowsToastOnly() async {
        service.setWindowFocused(true)
        service.deliver(notification())
        await drain()

        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertEqual(attentions.count, 1)
    }

    func testFocusedTerminalInFocusedWindowShowsNothing() async {
        service.setWindowFocused(true)
        service.deliver(notification(focused: true))
        await drain()

        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertTrue(attentions.isEmpty)
    }

    func testDisabledKindIsDropped() async {
        service.updateSettings(NotificationSettings(agentFinished: false, needsInput: true))
        service.deliver(notification(.finished))
        service.deliver(notification(.failed))
        service.deliver(notification(.needsInput))
        await drain()

        XCTAssertEqual(presenter.presented.count, 1)
        XCTAssertEqual(attentions.map(\.kind), [.needsInput])
    }

    func testSoundSettingIsPassedThrough() {
        service.updateSettings(NotificationSettings(sound: false))
        service.deliver(notification())
        XCTAssertEqual(presenter.presented.first?.sound, false)
    }

    func testCooldownIsPerCheckout() async {
        service.deliver(notification(group: "/a"))
        service.deliver(notification(group: "/a"))
        service.deliver(notification(group: "/b"))
        await drain()
        XCTAssertEqual(presenter.presented.count, 2, "aynı checkout'ta 5 sn içinde ikinci OS bildirimi gitmez")
        XCTAssertEqual(attentions.count, 3, "toast bekleme süresine tabi değil")

        clock += NotificationService.defaultCooldown
        service.deliver(notification(group: "/a"))
        XCTAssertEqual(presenter.presented.count, 3)
    }

    func testDismissAndRemovalClearDeliveredNotification() {
        let id = TerminalID()
        service.dismiss(id)
        service.terminalRemoved(id)
        XCTAssertEqual(presenter.removed, [id.description, id.description])
    }

    func testPermissionRequestedOnce() async {
        await service.requestPermissionIfNeeded()
        await service.requestPermissionIfNeeded()
        XCTAssertEqual(presenter.authorizationRequestCount, 1)
    }
}
