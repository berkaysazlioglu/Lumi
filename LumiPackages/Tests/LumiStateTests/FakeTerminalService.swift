import Foundation
import LumiKit

/// TerminalServicing fake'i (design/00 §3 test ikamesi deseni).
@MainActor
final class FakeTerminalService: TerminalServicing {
    private let broadcaster = EventBroadcaster<TerminalEvent>()

    private(set) var spawnedMetas: [TerminalMeta] = []
    private(set) var killedIDs: [TerminalID] = []
    private(set) var focusCalls: [TerminalID?] = []
    private(set) var maxTerminalsValue = 12

    var terminals: [TerminalMeta] { spawnedMetas }

    @discardableResult
    func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        let meta = TerminalMeta(
            id: TerminalID(),
            name: "Terminal \(spawnedMetas.count + 1)",
            repoPath: repoPath,
            createdAt: Date(),
            task: task
        )
        spawnedMetas.append(meta)
        broadcaster.send(.spawned(meta))
        return meta
    }

    func write(id: TerminalID, text: String) throws {}

    func kill(id: TerminalID) throws {
        killedIDs.append(id)
    }

    func killAll() {}
    func resize(id: TerminalID, cols: Int, rows: Int) {}

    func setFocused(_ id: TerminalID?) {
        focusCalls.append(id)
    }

    func setWindowFocused(_ focused: Bool) {}

    func setMaxTerminals(_ n: Int) {
        maxTerminalsValue = n
    }

    func events() -> AsyncStream<TerminalEvent> {
        broadcaster.stream()
    }

    func outputStream(id: TerminalID) -> AsyncStream<String>? {
        outputBroadcaster(for: id).stream()
    }

    func emit(_ event: TerminalEvent) {
        broadcaster.send(event)
    }

    private var outputBroadcasters: [TerminalID: EventBroadcaster<String>] = [:]

    func emitOutput(_ id: TerminalID, _ text: String) {
        outputBroadcaster(for: id).send(text)
    }

    private func outputBroadcaster(for id: TerminalID) -> EventBroadcaster<String> {
        if let existing = outputBroadcasters[id] {
            return existing
        }
        let fresh = EventBroadcaster<String>()
        outputBroadcasters[id] = fresh
        return fresh
    }
}
