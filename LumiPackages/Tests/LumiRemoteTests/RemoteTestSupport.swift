import Foundation
import LumiKit
@testable import LumiRemote

/// Socket oturumu testleri için provider fake'i — terminal alt sistemi yok.
actor FakeRemoteProvider: RemoteTerminalProviding {
    private var summaries: [RemoteTerminalSummary]
    private var screens: [String: TerminalScreenSnapshot]
    private var signalContinuations: [String: AsyncStream<String>.Continuation] = [:]
    private(set) var inputs: [(id: String, rawText: String)] = []
    private(set) var prompts: [(id: String, prompt: String)] = []

    init(summaries: [RemoteTerminalSummary] = [], screens: [String: TerminalScreenSnapshot] = [:]) {
        self.summaries = summaries
        self.screens = screens
    }

    func listTerminals() async -> [RemoteTerminalSummary] { summaries }

    func terminal(id: String) async -> RemoteTerminalSummary? {
        summaries.first { $0.id == id }
    }

    func screenSnapshot(id: String) async -> TerminalScreenSnapshot? { screens[id] }

    func sendInput(id: String, rawText: String) async -> Bool {
        guard summaries.contains(where: { $0.id == id }) else { return false }
        inputs.append((id, rawText))
        return true
    }

    func sendPrompt(id: String, prompt: String) async -> Bool {
        guard summaries.contains(where: { $0.id == id }) else { return false }
        prompts.append((id, prompt))
        return true
    }

    func outputSignal(id: String) async -> AsyncStream<String>? {
        guard summaries.contains(where: { $0.id == id }) else { return nil }
        let (stream, continuation) = AsyncStream<String>.makeStream()
        signalContinuations[id] = continuation
        return stream
    }

    // MARK: - Test sürücüleri

    func emitOutput(_ id: String, _ text: String = "chunk") {
        signalContinuations[id]?.yield(text)
    }

    func setScreen(_ id: String, _ text: String) {
        screens[id] = makeSnapshot(history: text)
    }

    func updateStatus(_ id: String, to status: String) {
        summaries = summaries.map { summary in
            guard summary.id == id else { return summary }
            return RemoteTerminalSummary(
                id: summary.id, name: summary.name, repoPath: summary.repoPath,
                repoName: summary.repoName, status: status,
                task: summary.task, title: summary.title
            )
        }
    }

    func removeTerminal(_ id: String) {
        summaries.removeAll { $0.id == id }
    }
}

/// WS `send`/`close` closure'larının thread-safe kayıt defteri.
final class SentMessageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    private var closedFlag = false

    func append(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }

    func markClosed() {
        lock.lock()
        closedFlag = true
        lock.unlock()
    }

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closedFlag
    }
}

func makeSnapshot(history: String) -> TerminalScreenSnapshot {
    TerminalScreenSnapshot(
        history: history,
        screen: [[TerminalScreenRun(text: "ekran-satırı")]]
    )
}

func makeSummary(
    id: String = "11111111-1111-1111-1111-111111111111",
    status: String = "working"
) -> RemoteTerminalSummary {
    RemoteTerminalSummary(
        id: id, name: "Terminal 1", repoPath: "/tmp/demo", repoName: "demo",
        status: status, task: nil, title: nil
    )
}

/// Zamanlamalı (tick tabanlı) davranışlar için koşul bekleyici.
func waitUntil(
    timeout: TimeInterval = 3,
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}
