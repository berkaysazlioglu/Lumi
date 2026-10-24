import Foundation
import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

/// Karar 136: sağ panelin hedef checkout'u (`NavigationStore.toolsRepoPath`) —
/// repo route'unda aktif repo, All Terminals / Custom View'da seçili terminalin
/// checkout'u; serbest terminalde hiçbir zaman (karar 108 güvenlik kapısı).
@MainActor
final class ToolsRepoTests: XCTestCase {
    private var service: FakeTerminalService!
    private var shared: SharedStores!
    private var announcements: [ToolsChange] = []

    private struct ToolsChange: Equatable {
        let old: String?
        let new: String?
    }

    private var navigation: NavigationStore { shared.navigation }
    private var terminals: TerminalListStore { shared.terminals }

    override func setUp() async throws {
        service = FakeTerminalService()
        shared = SharedStores.make(config: FakeConfigService(), terminal: service, toastAutoDismissAfter: 60)
        navigation.projectOrder = { ["/r/alpha", "/r/beta"] }
        announcements = []
        navigation.onActiveRepoChanged = { [weak self] old, new in
            self?.announcements.append(ToolsChange(old: old, new: new))
        }
    }

    @discardableResult
    private func spawn(_ name: String, repo: String) -> TerminalMeta {
        let meta = TerminalMeta(id: TerminalID(), name: name, repoPath: repo, createdAt: Date())
        terminals.apply(.spawned(meta))
        return meta
    }

    func testRepoRouteTargetsTheRepo() {
        navigation.openTab("/r/alpha")
        XCTAssertEqual(navigation.toolsRepoPath, "/r/alpha")
        XCTAssertEqual(announcements, [ToolsChange(old: nil, new: "/r/alpha")])
    }

    func testAllTerminalsFollowsTheSelectedTerminal() {
        let alpha = spawn("a", repo: "/r/alpha")
        let beta = spawn("b", repo: "/r/beta")
        navigation.setRoute(.content(.allTerminals))
        announcements = []

        terminals.focus(alpha.id)
        XCTAssertEqual(navigation.toolsRepoPath, "/r/alpha")
        terminals.focus(beta.id)
        XCTAssertEqual(navigation.toolsRepoPath, "/r/beta")
        terminals.focus(beta.id)

        XCTAssertEqual(announcements, [
            ToolsChange(old: "/r/beta", new: "/r/alpha"),
            ToolsChange(old: "/r/alpha", new: "/r/beta"),
        ], "aynı checkout'ta yeniden duyurulmaz")
    }

    func testLooseTerminalNeverBecomesTheTarget() {
        let alpha = spawn("a", repo: "/r/alpha")
        let loose = spawn("home", repo: "/Users/me")
        navigation.setRoute(.content(.allTerminals))
        terminals.focus(alpha.id)

        terminals.focus(loose.id)

        XCTAssertNil(navigation.toolsRepoPath)
        XCTAssertEqual(announcements.last, ToolsChange(old: "/r/alpha", new: nil))
    }

    func testCustomViewTargetsOnlyItsMembers() {
        let alpha = spawn("a", repo: "/r/alpha")
        let beta = spawn("b", repo: "/r/beta")
        let view = terminals.createCustomView(with: alpha.id)!
        navigation.setRoute(.content(.customView(view)))
        XCTAssertEqual(navigation.toolsRepoPath, "/r/alpha")

        terminals.focus(beta.id)

        XCTAssertNil(navigation.toolsRepoPath, "üye olmayan terminal view'ın hedefi olmaz")
    }

    func testNonSurfaceRouteClearsTheTarget() {
        let alpha = spawn("a", repo: "/r/alpha")
        navigation.setRoute(.content(.allTerminals))
        terminals.focus(alpha.id)

        navigation.setRoute(.content(ContentRouteID("tasks")))

        XCTAssertNil(navigation.toolsRepoPath)
        XCTAssertEqual(announcements.last, ToolsChange(old: "/r/alpha", new: nil))
    }

    func testClosingTheTargetsTabOnAllTerminalsUnwatchesIt() {
        navigation.openTab("/r/alpha")
        let alpha = spawn("a", repo: "/r/alpha")
        navigation.setRoute(.content(.allTerminals))
        terminals.focus(alpha.id)
        announcements = []

        navigation.closeTab("/r/alpha")
        terminals.apply(.exited(alpha.id, code: 0))

        XCTAssertNil(navigation.toolsRepoPath)
        XCTAssertEqual(announcements.first?.old, "/r/alpha")
    }
}
