import Foundation
import LumiWire

extension DemoTranscripts {
    // MARK: word-puzzle ▸ daily-rewards (pending Bash approval)

    static func rewards(_ startMs: Int) -> DemoChatBuilder {
        var b = DemoChatBuilder(prefix: DemoIDs.rewards, startMs: startMs)
        b.user("Build the daily rewards calendar: 7 day cells, today highlighted, claimed days checked.")
        b.tool("Glob", "Sources/App/Rewards/**/*.swift", output: """
            Sources/App/Rewards/RewardsCalendar.swift
            Sources/App/Rewards/RewardDayCell.swift
            Sources/App/Rewards/RewardsStore.swift
            """)
        b.say("""
            The calendar exists but computes weeks by hand. I'd like to add **date-fns** for the \
            web preview build so the week math matches the Swift side (`Calendar.firstWeekday`).
            """)
        b.pendingTool("Bash", "npm install date-fns@4")
        return b
    }

    // MARK: Lumi ▸ Investigate flaky ProjectTree test (error)

    static func flaky(_ startMs: Int) -> DemoChatBuilder {
        var b = DemoChatBuilder(prefix: DemoIDs.flaky, startMs: startMs)
        b.user("ProjectTreeTests.testLooseGroupsSortByPath fails about 1 in 5 runs on CI. Find out why.")
        b.tool("Bash", "swift test --filter ProjectTreeTests", output: """
            Test Case '-[ProjectTreeTests testLooseGroupsSortByPath]' started.
            ProjectTreeTests.swift:64: error: XCTAssertEqual failed: \
            ("["~/Desktop", "~"]") is not equal to ("["~", "~/Desktop"]")
            Test Case '-[ProjectTreeTests testLooseGroupsSortByPath]' failed (0.004 seconds).
            Executed 9 tests, with 1 failure (0 unexpected) in 0.031 seconds
            error: fatalError
            """, isError: true)
        b.say("""
            Reproduced. `looseGroups` builds a `Dictionary` keyed by folder and maps its `values` — \
            *dictionary order isn't stable*, so the test only passes when hashing happens to agree.
            """)
        b.tool("Read", "LumiPackages/Sources/LumiKit/Models/ProjectTree.swift", output: """
            static func looseGroups(_ terminals: [TerminalMeta],
                                    _ owners: [String: [String]]) -> [OtherGroupNode] {
                let byFolder = Dictionary(grouping: terminals.filter(\\.isLoose), by: \\.cwd)
                return byFolder.map { folder, items in
                    OtherGroupNode(path: folder, label: shortPath(folder), agentIds: items.map(\\.id))
                }
            }
            """)
        b.say("""
            ## Root cause
            `byFolder.map` iterates in hash order. Fix: sort by `path` before returning.

            I tried to run the full suite to confirm, but the build broke on an unrelated file:
            """)
        b.tool("Bash", "swift build", output: """
            error: emit-module command failed with exit code 1
            LumiServices/Remote/RemoteService.swift:212:17: error: cannot find 'projectsPayload' in scope
            ninja: build stopped: subcommand failed.
            """, isError: true)
        b.say("**Blocked:** `RemoteService.swift` doesn't compile on this branch. Rebase on `main` and I'll retry.")
        return b
    }

    // MARK: liman ▸ Port shipping API to async/await (short)

    static func liman(_ startMs: Int) -> DemoChatBuilder {
        var b = DemoChatBuilder(prefix: DemoIDs.liman, startMs: startMs)
        b.user("Convert ShippingClient from completion handlers to async/await.")
        b.tool("Read", "Sources/Liman/ShippingClient.swift", output: """
            func fetchManifest(id: String, completion: @escaping (Result<Manifest, Error>) -> Void) {
                session.dataTask(with: request(for: id)) { data, _, error in
                    completion(Result { try decode(data, error) })
                }.resume()
            }
            """)
        b.say("""
            Converted `fetchManifest` and `track(_:)`:

            ```swift
            func fetchManifest(id: String) async throws -> Manifest {
                let (data, _) = try await session.data(for: request(for: id))
                return try JSONDecoder().decode(Manifest.self, from: data)
            }
            ```

            The old completion API remains as a thin wrapper, marked `@available(*, deprecated)`.
            """)
        return b
    }

    // MARK: ~ ▸ Clean up Downloads folder (loose)

    static func home(_ startMs: Int) -> DemoChatBuilder {
        var b = DemoChatBuilder(prefix: DemoIDs.home, startMs: startMs)
        b.user("What's taking space in ~/Downloads?")
        b.tool("Bash", "du -sh ~/Downloads/* | sort -rh | head -5", output: """
            4.1G\t/Users/demo/Downloads/Xcode_26.1.xip
            1.2G\t/Users/demo/Downloads/unity-hub-backup.zip
            380M\t/Users/demo/Downloads/screen-recordings
             96M\t/Users/demo/Downloads/fonts
             12M\t/Users/demo/Downloads/invoices
            """)
        b.say("""
            The top two are installers you've likely already used:

            - `Xcode_26.1.xip` — **4.1 GB**
            - `unity-hub-backup.zip` — **1.2 GB**

            Deleting both frees ~5.3 GB. Want me to move them to the Trash?
            """)
        return b
    }
}
