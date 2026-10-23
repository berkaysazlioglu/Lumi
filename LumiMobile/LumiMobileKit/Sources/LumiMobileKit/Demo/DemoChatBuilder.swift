import Foundation
import LumiWire

/// Builds Claude-transcript-shaped chat messages the way the Mac decodes them:
/// a tool call is an assistant message with one `.toolCall` block, its result a
/// user message with one `.toolResult` block (both fold into the preceding turn).
struct DemoChatBuilder {
    private(set) var messages: [ChatMessage] = []
    private let prefix: String
    private var counter: Int
    private var timestampMs: Int
    private var turnId: String?

    /// Gap between consecutive canned messages.
    static let messageSpacingMs = 15_000

    init(prefix: String, startMs: Int) {
        self.prefix = prefix
        self.timestampMs = startMs
        self.counter = 0
    }

    /// Later appends are stamped no earlier than `ms` (canned history is in the past).
    mutating func advanceClock(to ms: Int) {
        timestampMs = max(timestampMs, ms)
    }

    /// A user prompt; starts a new turn.
    mutating func user(_ text: String) {
        turnId = "\(prefix)-turn-\(counter)"
        add(.user, [.text(text, presentation: nil)])
    }

    /// Assistant prose (markdown).
    mutating func say(_ text: String) {
        add(.assistant, [.text(text, presentation: nil)])
    }

    /// A tool call plus its result, like the Claude TUI's `Bash(swift test)` row.
    mutating func tool(_ name: String, _ preview: String, output: String, isError: Bool = false) {
        add(.assistant, [.toolCall(name: name, inputPreview: preview, state: "completed")])
        add(.user, [.toolResult(output: output, isError: isError)])
    }

    /// A tool call that is still waiting (e.g. on a permission prompt).
    mutating func pendingTool(_ name: String, _ preview: String) {
        add(.assistant, [.toolCall(name: name, inputPreview: preview, state: "running")])
    }

    /// A lone tool result (resolves an earlier `pendingTool`).
    mutating func toolResult(_ output: String, isError: Bool = false) {
        add(.user, [.toolResult(output: output, isError: isError)])
    }

    /// Flips `running` tool calls to `completed`; returns the rewritten messages
    /// (same ids — `chat_append` upserts them in place).
    mutating func completeRunningTools() -> [ChatMessage] {
        var changed: [ChatMessage] = []
        for (index, message) in messages.enumerated() {
            guard case let .toolCall(name, preview, "running")? = message.blocks.first else { continue }
            let done = ChatMessage(id: message.id, role: message.role,
                                   blocks: [.toolCall(name: name, inputPreview: preview, state: "completed")],
                                   timestampMs: message.timestampMs, turnId: message.turnId)
            messages[index] = done
            changed.append(done)
        }
        return changed
    }

    private mutating func add(_ role: ChatRole, _ blocks: [ChatBlock]) {
        counter += 1
        messages.append(ChatMessage(id: "\(prefix)-m\(counter)", role: role, blocks: blocks,
                                    timestampMs: timestampMs, turnId: turnId ?? "\(prefix)-turn-0"))
        timestampMs += Self.messageSpacingMs
    }
}

/// Canned assistant replies for phone-sent messages.
enum DemoReplies {
    /// First sentence shown as live streaming text while the reply is "thinking".
    static func streamingPreview(for text: String) -> String {
        "Looking into “\(clipped(text))” — reading the relevant files first."
    }

    /// Tool activity + final markdown answer for a phone-sent prompt.
    static func reply(to text: String, cwd: String, builder: inout DemoChatBuilder) {
        builder.say("Looking into “\(clipped(text))” — reading the relevant files first.")
        builder.tool("Grep", "\"TODO|FIXME\" in \(cwd)", output: """
            Sources/App/Board/TileView.swift:42:    // TODO: clamp overshoot on the bottom row
            Sources/App/Rewards/RewardsCalendar.swift:88:    // FIXME: week starts on Sunday in en_US
            Tests/AppTests/TileDropTests.swift:17:    // TODO: cover the combo drop path
            """)
        builder.say("""
            ## Summary

            I checked the code paths related to your request. Here's what I found:

            1. **`TileView.swift`** still has an open TODO about the bottom-row overshoot.
            2. *RewardsCalendar* assumes a Sunday week start — wrong for most locales.
            3. `TileDropTests` doesn't cover combo drops yet.

            > This is a demo reply — no files were changed.

            Want me to start with item 1?
            """)
    }

    /// Follow-up after the user answers the `rewards` Bash approval.
    static func approvalOutcome(allowed: Bool, builder: inout DemoChatBuilder) {
        guard allowed else {
            builder.toolResult("The user doesn't want to proceed with this tool use.", isError: true)
            builder.say("Understood — I'll do the week math with `Calendar` instead of adding a dependency.")
            return
        }
        builder.toolResult("""
            added 1 package, and audited 412 packages in 3s

            87 packages are looking for funding
              run `npm fund` for details

            found 0 vulnerabilities
            """)
        builder.say("""
            `date-fns@4` is installed. The calendar now uses `startOfWeek(date, { weekStartsOn: 1 })` \
            so **Monday** is the first column. Next: wiring the claimed-day state into `RewardDayCell`.
            """)
    }

    private static let previewLimit = 40

    private static func clipped(_ text: String) -> String {
        let flat = normalizeChatUserText(text)
        return flat.count > previewLimit ? String(flat.prefix(previewLimit)) + "…" : flat
    }
}
