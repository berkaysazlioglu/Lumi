import Foundation
import LumiKit

/// Preset servis testleri için minimal stub'lar.
@MainActor
final class StubTerminalService: TerminalServicing {
    private let eventBroadcaster = EventBroadcaster<TerminalEvent>()
    private let outputBroadcaster = EventBroadcaster<String>()

    private(set) var spawnCalls: [(repoPath: String, task: String?)] = []
    private(set) var writeCalls: [(id: TerminalID, text: String)] = []
    var terminals: [TerminalMeta] = []

    @discardableResult
    func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        spawnCalls.append((repoPath, task))
        let meta = TerminalMeta(
            id: TerminalID(), name: "stub", repoPath: repoPath, createdAt: Date(), task: task
        )
        terminals.append(meta)
        return meta
    }

    func write(id: TerminalID, text: String) throws {
        writeCalls.append((id, text))
    }

    func kill(id: TerminalID) throws {}
    func killAll() {}
    func resize(id: TerminalID, cols: Int, rows: Int) {}
    func setFocused(_ id: TerminalID?) {}
    func setWindowFocused(_ focused: Bool) {}
    func setMaxTerminals(_ n: Int) {}

    func events() -> AsyncStream<TerminalEvent> {
        eventBroadcaster.stream()
    }

    func outputStream(id: TerminalID) -> AsyncStream<String>? {
        outputBroadcaster.stream()
    }

    func emitOutput(_ text: String) {
        outputBroadcaster.send(text)
    }
}

actor StubConfigService: ConfigServicing {
    var stored = AppConfig.defaults

    func config() -> AppConfig { stored }
    func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) throws {
        mutate(&stored)
    }
    func uiState() -> UIState { .defaults }
    func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) {}
    func isFirstRun() -> Bool { false }
    func flushPendingWrites() {}
    func events() -> AsyncStream<ConfigEvent> {
        AsyncStream { $0.finish() }
    }
}
