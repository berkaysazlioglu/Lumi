import Foundation
import LumiWire

/// Stable ids of the canned demo sessions (also used by tests).
public enum DemoIDs {
    public static let tiles = "demo-wp-tiles"          // claude, working (live turn)
    public static let hints = "demo-wp-hints"          // codex terminal, waiting-unseen
    public static let rewards = "demo-wp-rewards"      // claude, awaiting a Bash approval
    public static let relay = "demo-lumi-relay"        // claude, waiting-seen, rich transcript
    public static let flaky = "demo-lumi-flaky"        // claude, error (failing test run)
    public static let liman = "demo-liman-async"       // claude, idle
    public static let home = "demo-home-cleanup"       // claude, loose in ~
    public static let shell = "demo-desktop-shell"     // plain zsh, loose in ~/Desktop

    /// The pending approval shown on `rewards`.
    public static let rewardsPromptItem = "demo-prompt-npm-install"
}

/// Canned paths of the fake Mac (`/Users/demo/...`).
enum DemoPaths {
    static let home = "/Users/demo"
    static let desktop = "/Users/demo/Desktop"
    static let wkspaces = "/Users/demo/wkspaces"
    static let workspacesRoot = "/Users/demo/lumi/workspaces"
    static let wordPuzzle = "/Users/demo/wkspaces/word-puzzle"
    static let dailyRewards = "/Users/demo/lumi/workspaces/word-puzzle/daily-rewards"
    static let lumi = "/Users/demo/wkspaces/Lumi"
    static let liman = "/Users/demo/wkspaces/liman"
    static let collectioner = "/Users/demo/wkspaces/Collectioner"
    static let notes = "/Users/demo/wkspaces/notes"

    /// `/Users/demo/x` → `~/x` (the Mac's short-path label for Other groups).
    static func shortLabel(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

/// The fake Mac's initial state: projects tree, Other groups and sessions.
enum DemoData {
    static let terminalCols = 80
    static let terminalRows = 24
    static let opus = "claude-opus-4-5"
    static let sonnet = "claude-sonnet-4-5"
    static let codexModel = "gpt-5-codex"
    private static let msPerMinute = 60_000.0

    static let display = MacDisplay(terminalFontFamily: "")

    static let looseLocations = [
        LooseLocation(path: DemoPaths.home, label: "~"),
        LooseLocation(path: DemoPaths.wkspaces, label: "~/wkspaces"),
    ]

    static let addable = [
        Repo(name: "sand-blocks", path: "/Users/demo/wkspaces/sand-blocks"),
        Repo(name: "toolbox", path: "/Users/demo/wkspaces/Tools/toolbox"),
        Repo(name: "orca", path: "/Users/demo/wkspaces/orca"),
    ]

    static let projects: [ProjectNode] = [
        ProjectNode(name: "word-puzzle", path: DemoPaths.wordPuzzle, checkouts: [
            CheckoutNode(kind: "original", title: "main", branch: "main", scm: "git",
                         path: DemoPaths.wordPuzzle, agentIds: [DemoIDs.tiles, DemoIDs.hints]),
            CheckoutNode(kind: "workspace", title: "daily-rewards", branch: "feat/daily-rewards",
                         scm: "git", path: DemoPaths.dailyRewards, agentIds: [DemoIDs.rewards]),
        ], appearance: ProjectAppearance(color: .lime, icon: .emoji("🏖️"))),
        ProjectNode(name: "Lumi", path: DemoPaths.lumi, checkouts: [
            CheckoutNode(kind: "original", title: "dev", branch: "main", scm: "git",
                         path: DemoPaths.lumi, agentIds: [DemoIDs.relay, DemoIDs.flaky]),
        ], appearance: ProjectAppearance(color: .pink, icon: .emoji("🐙"), rootTitle: "dev")),
        ProjectNode(name: "liman", path: DemoPaths.liman, checkouts: [
            CheckoutNode(kind: "original", title: "main", branch: "main", scm: "git",
                         path: DemoPaths.liman, agentIds: [DemoIDs.liman]),
        ], appearance: ProjectAppearance(color: .blue, icon: .emoji("🚢"))),
        ProjectNode(name: "Collectioner", path: DemoPaths.collectioner, checkouts: [
            CheckoutNode(kind: "original", title: "main", branch: "/main", scm: "plastic",
                         path: DemoPaths.collectioner, agentIds: []),
        ], appearance: ProjectAppearance(icon: .emoji("📚"))),
        ProjectNode(name: "notes", path: DemoPaths.notes, checkouts: [
            CheckoutNode(kind: "original", title: "main", branch: nil, scm: "none",
                         path: DemoPaths.notes, agentIds: []),
        ]),
    ]

    static let others = [
        OtherGroupNode(path: DemoPaths.home, label: "~", agentIds: [DemoIDs.home]),
        OtherGroupNode(path: DemoPaths.desktop, label: "~/Desktop", agentIds: [DemoIDs.shell]),
    ]

    /// Sessions with `lastActivityAt` relative to `nowMs`.
    static func sessions(nowMs: Double) -> [SessionMeta] {
        func ago(_ minutes: Double) -> Double { nowMs - minutes * msPerMinute }
        return [
            chat(DemoIDs.tiles, "word-puzzle", "working", "Fix tile drop animation", opus, ago(0)),
            SessionMeta(id: DemoIDs.hints, repoName: "word-puzzle", status: "waiting-unseen",
                        title: "Hint button cooldown", model: codexModel,
                        cols: terminalCols, rows: terminalRows, kind: "terminal",
                        provider: "codex", lastActivityAt: ago(3)),
            chat(DemoIDs.rewards, "word-puzzle", "working", "Daily rewards calendar UI", sonnet, ago(1),
                 awaitingDecision: true),
            chat(DemoIDs.relay, "Lumi", "waiting-seen", "Add relay reconnect backoff", opus, ago(12)),
            chat(DemoIDs.flaky, "Lumi", "error", "Investigate flaky ProjectTree test", opus, ago(26)),
            chat(DemoIDs.liman, "liman", "idle", "Port shipping API to async/await", sonnet, ago(95)),
            chat(DemoIDs.home, "demo", "idle", "Clean up Downloads folder", sonnet, ago(240)),
            SessionMeta(id: DemoIDs.shell, repoName: "Desktop", status: "idle", title: "zsh",
                        cols: terminalCols, rows: terminalRows, kind: "terminal",
                        provider: nil, lastActivityAt: ago(7)),
        ]
    }

    /// A Claude session as the Mac broadcasts it (Claude terminals are `kind: "chat"`).
    static func chat(_ id: String, _ repo: String, _ status: String, _ title: String?,
                     _ model: String?, _ lastActivityAt: Double,
                     awaitingDecision: Bool = false) -> SessionMeta {
        SessionMeta(id: id, repoName: repo, status: status, title: title, model: model,
                    cols: terminalCols, rows: terminalRows, kind: "chat", provider: "claude",
                    lastActivityAt: lastActivityAt, awaitingDecision: awaitingDecision)
    }

    /// The Bash approval pending on `rewards` (Claude TUI "Do you want to proceed?").
    static let rewardsPrompt = ChatPrompt(
        itemId: DemoIDs.rewardsPromptItem, revision: 1, kind: .approval,
        title: "Bash(npm install date-fns@4)",
        detail: "Add date-fns for the rewards calendar week math",
        options: [
            ChatPromptOption(id: "allow", label: "Yes", description: nil),
            ChatPromptOption(id: "allow-always", label: "Yes, and don't ask again for npm install",
                             description: nil),
            ChatPromptOption(id: "deny", label: "No, and tell Claude what to do differently",
                             description: nil),
        ],
        state: .pending, selectedOptionId: nil)

    /// The live turn of `tiles`: started a little before "now".
    static func tilesTurn(nowMs: Double) -> ChatTurnStatus {
        ChatTurnStatus(working: true, startedAtMs: Int(nowMs - 2 * msPerMinute), tool: "Edit")
    }

    /// The `rewards` turn is open while Claude waits on the Bash approval.
    static func rewardsTurn(nowMs: Double) -> ChatTurnStatus {
        ChatTurnStatus(working: true, startedAtMs: Int(nowMs - msPerMinute), tool: "Bash")
    }

    /// Live streaming text of the `tiles` turn; revealed word by word.
    static let tilesStreaming = """
        The drop now eases with a spring instead of the linear `lerp`. I'm also clamping \
        the overshoot in `TileView.settle()` so tiles on the bottom row don't bounce through \
        the board frame. Next I'll re-run **TileDropTests** to confirm the timing budget \
        (≤ 180 ms) still holds.
        """
}

extension SessionMeta {
    /// Copy with changed live fields (SessionMeta is immutable).
    func demoUpdated(status: String? = nil, awaitingDecision: Bool? = nil,
                     lastActivityAt: Double? = nil, model: String? = nil) -> SessionMeta {
        SessionMeta(id: id, repoName: repoName, status: status ?? self.status, title: title,
                    model: model ?? self.model, cols: cols, rows: rows, kind: kind, provider: provider,
                    lastActivityAt: lastActivityAt ?? self.lastActivityAt,
                    awaitingDecision: awaitingDecision ?? self.awaitingDecision)
    }
}
