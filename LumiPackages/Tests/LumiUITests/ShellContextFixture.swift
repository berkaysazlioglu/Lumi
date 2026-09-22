import AppKit
import Foundation
import LumiKit
import LumiState
import LumiTestSupport
@testable import LumiUI

/// Test için tamamen sahte servislerle kurulmuş bir `ShellContext`.
///
/// Registry çözümlemeleri (`isAvailable`) bağlam ister; bu fixture sayesinde o
/// çözümlemeler **view render etmeden** doğrulanabilir.
/// Kabuk yan etkilerinin kaydı (karar 57 testleri): Finder / varsayılan
/// uygulama / tarayıcı çağrıları.
@MainActor
final class ShellActionRecorder {
    var revealedPaths: [String] = []
    var openedPaths: [String] = []
    var openedURLs: [URL] = []
}

@MainActor
struct ShellContextFixture {
    let context: ShellContext
    let recorder: ShellActionRecorder
    let shared: SharedStores
    let config: FakeConfigService
    let terminalService: FakeTerminalService
    let viewProvider: FakeTerminalViewProvider

    /// Terminal event stream'i tüketen store başlatılır: fixture gerçek
    /// `spawn` yolundan terminal üretebilsin diye (`apply` LumiState-internal).
    static func make(repo: FakeRepoService = FakeRepoService(), git: FakeGitService = FakeGitService(), workspaces: FakeWorkspaceService = FakeWorkspaceService()) async -> ShellContextFixture {
        let config = FakeConfigService()
        let recorder = ShellActionRecorder()
        let terminalService = FakeTerminalService()
        let viewProvider = FakeTerminalViewProvider()
        let shared = SharedStores.make(
            config: config,
            terminal: terminalService,
            viewProvider: viewProvider,
            toastAutoDismissAfter: 60
        )
        let system = FakeSystemService()
        let toasts = shared.toasts
        let repos = RepoStore(service: repo)
        let context = ShellContext(
            navigation: shared.navigation,
            layout: shared.layout,
            dialogs: shared.dialogs,
            terminals: shared.terminals,
            repos: repos,
            workspaces: ProjectWorkspaceStore(service: workspaces, config: config, repos: repos, toasts: toasts),
            quickCommands: QuickCommandStore(config: config, generator: FakeQuickCommandGenerator(), toasts: toasts),
            git: GitStore(git: git, toasts: toasts),
            plastic: PlasticStore(service: FakePlasticService(), toasts: toasts),
            commitAssistant: CommitMessageAssistant(generator: FakeCommitMessageGenerator(), toasts: toasts),
            agentHistory: AgentHistoryStore(service: FakeAgentHistoryService(), transfer: FakeAgentSessionTransferService(), toasts: toasts),
            fileViewer: FileViewerStore(git: git, toasts: toasts),
            settings: shared.settings,
            remote: RemoteStore(service: FakeRemoteService()),
            sessionSchedule: SessionScheduleStore(starter: FakeSessionStarterService()),
            promptQueue: PromptQueueStore(service: terminalService, toasts: toasts),
            toasts: toasts,
            onboarding: OnboardingStore(
                system: system,
                settings: shared.settings,
                toasts: toasts,
                onComplete: {}
            ),
            usage: [:],
            deepSeek: DeepSeekStore(service: FakeDeepSeekEnvironmentService(), toasts: toasts),
            deepSeekBalance: DeepSeekBalanceStore(service: FakeDeepSeekBalanceService()),
            claudeAccounts: ClaudeAccountStore(service: FakeClaudeAccountService(), toasts: toasts),
            codexAccounts: CodexAccountStore(service: FakeCodexAccountService(), toasts: toasts),
            terminalLinks: TerminalLinkActionStore(
                terminals: shared.terminals, repos: repos, workspaces: ProjectWorkspaceStore(service: workspaces, config: config, repos: repos, toasts: toasts)
            ),
            computerAwake: ComputerAwakeStore(
                terminals: shared.terminals, settings: shared.settings, assertion: FakeSleepAssertion()
            ),
            resourceUsage: ResourceUsageStore(
                terminals: shared.terminals, terminalService: terminalService, sampler: FakeProcessSampler()
            ),
            viewProvider: viewProvider,
            highlighter: StubHighlighter(),
            actions: ShellActions(
                chooseFolder: { nil },
                reveal: { _, _ in },
                trash: { _, _ in },
                revealPath: { recorder.revealedPaths.append($0) },
                openURL: { recorder.openedURLs.append($0) },
                openPath: { recorder.openedPaths.append($0) }
            )
        )
        await shared.terminals.start()
        context.terminalLinks.onIntent = { [weak context] intent in
            context?.performTerminalLinkIntent(intent)
        }
        return ShellContextFixture(
            context: context,
            recorder: recorder,
            shared: shared,
            config: config,
            terminalService: terminalService,
            viewProvider: viewProvider
        )
    }

    func stop() {
        shared.stop()
    }

    @discardableResult
    func openRepo(_ repoPath: String = "/r/alpha") -> ShellContextFixture {
        context.navigation.openTab(repoPath)
        return self
    }

    /// Gerçek spawn yolundan bir terminal üretir ve store'a düşmesini bekler.
    @discardableResult
    func spawnTerminal(
        named name: String = "t1",
        in repoPath: String = "/r/alpha"
    ) async throws -> TerminalMeta {
        let before = context.terminals.terminals.count
        context.terminals.spawn(in: repoPath, task: name)
        let deadline = Date().addingTimeInterval(2)
        while context.terminals.terminals.count == before {
            if Date() > deadline {
                throw ShellFixtureError.terminalDidNotAppear
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return context.terminals.terminals[before]
    }
}

enum ShellFixtureError: Error {
    case terminalDidNotAppear
}

/// FileViewer'ın gerçek `HighlightrEngine`'ini (JSCore) testlere sokmamak için.
final class StubHighlighter: SyntaxHighlighting {
    func highlight(code: String, fileName: String, fontSize: CGFloat) async -> NSAttributedString {
        NSAttributedString(string: code)
    }
}
