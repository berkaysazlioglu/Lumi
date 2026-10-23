import Foundation
import LumiWire

/// Canned Claude transcripts per demo session. Each returns the builder so later
/// phone-sent turns continue the same id/timestamp sequence.
enum DemoTranscripts {
    private static let msPerMinute = 60_000.0

    static func seed(nowMs: Double) -> [String: DemoChatBuilder] {
        func start(_ minutesAgo: Double) -> Int { Int(nowMs - minutesAgo * msPerMinute) }
        return [
            DemoIDs.tiles: tiles(start(9)),
            DemoIDs.relay: relay(start(40)),
            DemoIDs.rewards: rewards(start(6)),
            DemoIDs.flaky: flaky(start(35)),
            DemoIDs.liman: liman(start(110)),
            DemoIDs.home: home(start(250)),
        ]
    }

    // MARK: word-puzzle ▸ Fix tile drop animation (live turn)

    static func tiles(_ startMs: Int) -> DemoChatBuilder {
        var b = DemoChatBuilder(prefix: DemoIDs.tiles, startMs: startMs)
        b.user("Tiles snap into place instead of falling when a row clears. Can you fix the drop animation?")
        b.say("I'll start by looking at how the board schedules the drop.")
        b.tool("Read", "/Users/demo/wkspaces/word-puzzle/Sources/App/Board/TileView.swift", output: """
            import SwiftUI

            struct TileView: View {
                let tile: Tile
                @State private var offset: CGFloat = 0

                var body: some View {
                    LetterFace(letter: tile.letter)
                        .offset(y: offset)
                        .onChange(of: tile.row) { old, new in
                            offset = CGFloat(old - new) * Board.cellSize
                            offset = 0   // ← no animation context
                        }
                }
            }
            """)
        b.say("""
            Found it: `offset` is set and immediately reset **in the same transaction**, so SwiftUI \
            never interpolates. The fix is to reset inside `withAnimation`:

            ```swift
            .onChange(of: tile.row) { old, new in
                offset = CGFloat(old - new) * Board.cellSize
                withAnimation(.spring(duration: 0.18, bounce: 0.2)) {
                    offset = 0
                }
            }
            ```
            """)
        b.tool("Edit", "Sources/App/Board/TileView.swift", output: """
            Updated Sources/App/Board/TileView.swift with 3 additions and 1 removal
                 11                .onChange(of: tile.row) { old, new in
                 12                    offset = CGFloat(old - new) * Board.cellSize
                 13 -                  offset = 0   // ← no animation context
                 13 +                  withAnimation(.spring(duration: 0.18, bounce: 0.2)) {
                 14 +                      offset = 0
                 15 +                  }
            """)
        b.user("Looks better but bottom-row tiles bounce through the board frame.")
        b.tool("Grep", "\"bounce\" in Sources/App/Board", output: """
            Sources/App/Board/TileView.swift:13:  withAnimation(.spring(duration: 0.18, bounce: 0.2)) {
            Sources/App/Board/BoardView.swift:57:  // tiles may overshoot by bounce * cellSize
            """)
        return b
    }

    // MARK: Lumi ▸ Add relay reconnect backoff (rich markdown)

    static func relay(_ startMs: Int) -> DemoChatBuilder {
        var b = DemoChatBuilder(prefix: DemoIDs.relay, startMs: startMs)
        b.user("The phone hammers the relay when the Mac is offline. Add an exponential reconnect backoff.")
        b.tool("Read", "/Users/demo/wkspaces/Lumi/LumiPackages/Sources/LumiKit/Models/ProjectTree.swift",
               output: projectTreeExcerpt)
        b.tool("Grep", "\"reconnect\" in LumiMobile", output: """
            LumiMobile/LumiMobileKit/Sources/LumiMobileKit/RelayClient.swift:42:/// reconnects on disconnect
            LumiMobile/LumiMobileKit/Sources/LumiMobileKit/RelayClient.swift:137:            await sleep(1)
            LumiMobile/LumiMobileKit/Tests/LumiMobileKitTests/RelayClientTests.swift:88:    func testReconnects()
            """)
        b.say(relayPlan)
        b.tool("Edit", "LumiMobile/LumiMobileKit/Sources/LumiMobileKit/RelayClient.swift", output: """
            Updated RelayClient.swift with 18 additions and 2 removals
                 13 + /// 1, 2, 4, 8, … 60 s exponential back-off (mirrors the Mac-side ReconnectBackoff).
                 14 + public struct ReconnectBackoff: Sendable {
                 15 +     private var attempt = 0
                 16 +     private let capSeconds: Double = 60
            """)
        b.tool("Bash", "swift test --filter RelayClientTests", output: """
            Building for debugging...
            [14/14] Compiling LumiMobileKitTests RelayClientTests.swift
            Build complete! (6.42s)
            Test Suite 'RelayClientTests' started at 2026-10-23 10:14:02.118.
            Test Case '-[RelayClientTests testBackoffDoublesUpToCap]' passed (0.002 seconds).
            Test Case '-[RelayClientTests testBackoffResetsOnWelcome]' passed (0.011 seconds).
            Test Case '-[RelayClientTests testReconnects]' passed (0.034 seconds).
            Test Suite 'RelayClientTests' passed at 2026-10-23 10:14:02.171.
                 Executed 3 tests, with 0 failures (0 unexpected) in 0.047 (0.049) seconds
            """)
        b.say(relayDone)
        return b
    }

    private static let projectTreeExcerpt = """
        import Foundation

        /// Mac Projects panel mirrored to the phone (decision 91).
        public struct ProjectTree: Sendable {
            public let projects: [ProjectNode]
            public let others: [OtherGroupNode]

            public static func snapshot(from store: ProjectStore,
                                        terminals: [TerminalMeta]) -> ProjectTree {
                let owners = store.terminalOwnerPaths(terminals)
                let projects = store.projects.map { project in
                    ProjectNode(project, agents: owners[project.path] ?? [])
                }
                return ProjectTree(projects: projects, others: looseGroups(terminals, owners))
            }
        }
        """

    private static let relayPlan = """
        # Reconnect backoff

        Right now `RelayClient.run` sleeps a flat **1 s** between attempts, so an offline Mac \
        means ~3,600 handshakes an hour. Plan:

        ## Changes

        - Add `ReconnectBackoff` — doubles from 1 s, capped at *60 s*
        - Reset it when a `welcome` frame arrives (not on socket open — the relay accepts \
        before the Mac is known)
        - Keep `sleep` injectable so tests don't wait

        | Attempt | Delay | Cumulative |
        |---------|-------|------------|
        | 1 | 1 s | 1 s |
        | 2 | 2 s | 3 s |
        | 3 | 4 s | 7 s |
        | 7+ | 60 s | — |

        > The Mac side already uses the same curve, so both ends converge.
        """

    private static let relayDone = """
        Done. All 3 `RelayClientTests` pass.

        ### What changed
        1. `ReconnectBackoff` in `RelayClient.swift` (`nextDelay()` / `reset()`)
        2. `run(url:token:)` now awaits `sleep(backoff.nextDelay())`
        3. `backoff.reset()` on `welcome`

        Worst case the phone now retries **once a minute** instead of every second.
        """
}
