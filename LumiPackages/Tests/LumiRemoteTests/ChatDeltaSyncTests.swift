import Testing
import Foundation
import LumiKit
@testable import LumiRemote

/// Karar 130 (Faz 4): yalnız eksik mesajlar gider.
@Suite struct ChatDeltaSyncTests {
    private func message(_ id: String, chars: Int = 10) -> ChatMessage {
        ChatMessage(id: id, role: .assistant,
                    blocks: [.text(String(repeating: "a", count: chars), presentation: nil)],
                    timestampMs: nil, turnId: nil)
    }

    @Test func knownIdSendsOnlyLaterMessages() {
        let all = ["u1", "u2", "u3"].map { message($0) }
        #expect(ChatDeltaSync.plan(messages: all, afterId: "u1") == .delta([all[1], all[2]]))
        #expect(ChatDeltaSync.plan(messages: all, afterId: "u3") == .delta([]), "already up to date")
    }

    @Test func unknownOrUnstableIdFallsBackToSnapshot() {
        let all = [message("idx-0"), message("u1")]
        #expect(ChatDeltaSync.plan(messages: all, afterId: nil) == .snapshot)
        #expect(ChatDeltaSync.plan(messages: all, afterId: "gone") == .snapshot)
        #expect(ChatDeltaSync.plan(messages: all, afterId: "idx-0") == .snapshot)
    }

    @Test func oversizedDeltaFallsBackToSnapshot() {
        let all = [message("u0")] + (1...5).map { message("u\($0)", chars: 50_000) }
        #expect(ChatDeltaSync.plan(messages: all, afterId: "u0", budget: 100_000) == .snapshot)
    }
}
