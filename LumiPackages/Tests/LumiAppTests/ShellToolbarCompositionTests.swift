import AppKit
import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import LumiUI
import XCTest
@testable import LumiAppCore

/// **Canlı kompozisyonun** top bar karakterizasyonu (Faz 6.4/6.6).
///
/// `HeaderBarView` artık hiçbir kontrolün adını bilmiyor; bar'ın gerçek
/// dizilişi `AppComposition.live`'ın kaydettiği descriptor kümesinden türüyor.
/// Bu test o kümeyi (servis grafiği olmadan, aynı katkıcı listesiyle) kurar ve
/// üç bölgenin çözümlenmiş id sırasını kilitler — kayıt sırası ya da `order`
/// değeri yanlışlıkla değişirse burada kırılır.
@MainActor
final class ShellToolbarCompositionTests: XCTestCase {
    private var fixture: ShellFixture!
    private var registries: ShellRegistries!

    override func setUp() async throws {
        fixture = await ShellFixture.make()
        // `AppComposition.live` ile AYNI katkıcı listesi.
        registries = ShellComposition.makeRegistries(
            contributors: [
                TerminalFeatureAssembly(), RepoFeatureAssembly(), UsageFeatureAssembly(), StatusBarFeatureAssembly(),
            ]
        )
    }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
        registries = nil
    }

    private func ids(_ region: ToolbarRegion) -> [ToolbarItemID] {
        registries.toolbar.items(in: region, context: fixture.context).map(\.id)
    }

    // MARK: - Bölge karakterizasyonu

    /// Durum + global grup (sağdan sola: git · focus · usage). Settings karar
    /// 43'te alt bara taşındı. Codex göstergesi default kapalı (karar 32).
    func testTrailingRegionOrder() {
        fixture.openRepo()
        XCTAssertEqual(ids(.trailing), [
            .usageIndicator(.claude),
            .focusMode,
            .panelToggle(.right),
        ])
        XCTAssertFalse(ids(.trailing).contains(.settings), "settings alt barda (karar 43)")
    }

    // MARK: - Alt bar (karar 43)

    func testStatusBarRegions() {
        XCTAssertEqual(ids(.statusLeading), [.settings])
        XCTAssertEqual(ids(.statusTrailing), [.keepAwake, .resourceManager])
    }

    func testStatusBarItemsAreRouteIndependent() {
        fixture.context.navigation.setRoute(.content(ContentRouteID("placeholder")))
        XCTAssertEqual(ids(.statusLeading), [.settings])
        XCTAssertEqual(ids(.statusTrailing), [.keepAwake, .resourceManager])
    }

    func testTrailingRegionIncludesCodexOnlyWhenEnabled() {
        fixture.enableUsageIndicator(.codex)
        XCTAssertEqual(ids(.trailing).prefix(2).map(\.self), [
            .usageIndicator(.claude),
            .usageIndicator(.codex),
        ], "sıra AgentProvider.allCases sırasıdır (eski enabledProviders)")
    }

    /// Gezinme grubu: hamburger → logo → tab şeridi.
    func testLeadingRegionOrder() {
        XCTAssertEqual(ids(.leading), [.panelToggle(.left), .logo, .repoTabs])
    }

    /// Üretim grubu: grid ayarı → New <Provider> (+ ayraç, o öğenin parçası).
    func testCenterRegionOrder() {
        fixture.openRepo()
        XCTAssertEqual(ids(.center), [.gridSettings, .newTerminal])
    }

    /// `.bottom` yuvasının kayıtlı öğesi yok → toggle'ı bar'da görünmez.
    func testBottomSlotToggleIsHidden() {
        XCTAssertFalse(ids(.trailing).contains(.panelToggle(.bottom)))
        XCTAssertFalse(ids(.leading).contains(.panelToggle(.bottom)))
    }

    // MARK: - Üretim grubunun route kapısı (eski `if let activeTab`)

    func testProductionItemsAreHiddenWithoutAnActiveTab() {
        XCTAssertEqual(ids(.center), [], "tab yokken (.none) grid ayarı ve CTA çizilmez")
    }

    func testProductionItemsAreHiddenOnANonRepoRoute() {
        fixture.openRepo()
        XCTAssertEqual(ids(.center), [.gridSettings, .newTerminal])

        fixture.context.navigation.setRoute(.content(ContentRouteID("placeholder")))
        XCTAssertEqual(ids(.center), [], "repo-dışı route'ta üretim grubu bar'dan düşer")

        fixture.context.navigation.setRoute(.repo("/r/alpha"))
        XCTAssertEqual(ids(.center), [.gridSettings, .newTerminal], "geri dönüşte geri gelir")
    }

    /// Kabuğun diğer öğeleri route'tan bağımsızdır (repo-dışı bir görünümde de
    /// gezinme ve global kontroller durur).
    func testShellItemsSurviveANonRepoRoute() {
        fixture.context.navigation.setRoute(.content(ContentRouteID("placeholder")))
        XCTAssertEqual(ids(.leading), [.panelToggle(.left), .logo, .repoTabs])
        XCTAssertTrue(ids(.trailing).contains(.focusMode))
    }
}

/// Canlı kompozisyonun descriptor'larını değerlendirmek için tamamen sahte
/// servislerle kurulmuş `ShellContext` (LumiUITests'teki fixture'ın
/// LumiAppTests karşılığı — paylaşılan `LumiTestSupport` yalnız LumiKit'e
/// bağlı olduğu için store/UI tiplerini göremez).
@MainActor
private struct ShellFixture {
    let context: ShellContext
    let shared: SharedStores

    static func make() async -> ShellFixture {
        let config = FakeConfigService()
        let terminalService = FakeTerminalService()
        let shared = SharedStores.make(
            config: config,
            terminal: terminalService,
            viewProvider: FakeTerminalViewProvider(),
            toastAutoDismissAfter: 60
        )
        let git = FakeGitService()
        let toasts = shared.toasts
        let repos = RepoStore(service: FakeRepoService())
        let context = ShellContext(
            navigation: shared.navigation,
            layout: shared.layout,
            dialogs: shared.dialogs,
            terminals: shared.terminals,
            repos: repos,
            workspaces: ProjectWorkspaceStore(service: FakeWorkspaceService(), config: config, repos: repos, toasts: toasts),
            git: GitStore(git: git, toasts: toasts),
            plastic: PlasticStore(service: FakePlasticService(), toasts: toasts),
            commitAssistant: CommitMessageAssistant(generator: FakeCommitMessageGenerator(), toasts: toasts),
            agentHistory: AgentHistoryStore(service: FakeAgentHistoryService(), transfer: FakeAgentSessionTransferService(), toasts: toasts),
            fileViewer: FileViewerStore(git: git, toasts: toasts),
            settings: shared.settings,
            sessionSchedule: SessionScheduleStore(starter: FakeSessionStarterService()),
            promptQueue: PromptQueueStore(service: terminalService, toasts: toasts),
            toasts: toasts,
            onboarding: OnboardingStore(
                system: FakeSystemService(),
                settings: shared.settings,
                toasts: toasts,
                onComplete: {}
            ),
            usage: [:],
            computerAwake: ComputerAwakeStore(
                terminals: shared.terminals, settings: shared.settings, assertion: FakeSleepAssertion()
            ),
            resourceUsage: ResourceUsageStore(
                terminals: shared.terminals, terminalService: terminalService, sampler: FakeProcessSampler()
            ),
            viewProvider: FakeTerminalViewProvider(),
            highlighter: NoopHighlighter(),
            actions: ShellActions(chooseFolder: { nil }, reveal: { _, _ in }, trash: { _, _ in })
        )
        return ShellFixture(context: context, shared: shared)
    }

    func stop() {
        shared.stop()
    }

    func openRepo(_ repoPath: String = "/r/alpha") {
        context.navigation.openTab(repoPath)
    }

    func enableUsageIndicator(_ provider: AgentProvider) {
        context.settings.setUsageIndicators(
            context.settings.current.usageIndicators.setting(true, for: provider)
        )
    }
}

/// FileViewer'ın gerçek `HighlightrEngine`'ini (JSCore) testlere sokmamak için.
private final class NoopHighlighter: SyntaxHighlighting {
    func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString {
        NSAttributedString(string: code)
    }
}
