import Foundation
import LumiKit

/// Controller aynalarının sıralı akışı (karar 143 ek, docs/design/08).
///
/// Hub emülatörüyle aynı main-actor adımında beslenir: snapshot abonelik anında,
/// baytlar emülatöre girdikleri sırada gider — arada kayıp ya da tekrar olmaz.
/// Emülatör boyut değiştirince bayt iletimi durur; boyut `resyncDelay` boyunca sabit
/// kalınca yeni boyutta tek bir snapshot gider ve iletim sürer. Ayna hub'ın reflow'unu
/// taklit etmez, eski boyuttaki aynaya yeni boyut için yazılmış bayt da ulaşmaz.
@MainActor
final class RemoteMirrorFeed {
    /// Pencere sürüklenirken her karede değil, boyut oturunca bir kez snapshot.
    static let resyncDelay: Duration = .milliseconds(150)

    private let snapshot: @MainActor () -> TerminalMirrorEvent
    private var continuations: [UUID: AsyncStream<TerminalMirrorEvent>.Continuation] = [:]
    private var resyncTask: Task<Void, Never>?
    private(set) var isResyncing = false

    init(snapshot: @escaping @MainActor () -> TerminalMirrorEvent) {
        self.snapshot = snapshot
    }

    var hasSubscribers: Bool { !continuations.isEmpty }

    func subscribe() -> AsyncStream<TerminalMirrorEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TerminalMirrorEvent.self)
        let id = UUID()
        continuation.yield(snapshot())
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in self?.continuations[id] = nil }
        }
        return stream
    }

    /// Emülatöre az önce beslenen batch.
    func output(_ batch: Data) {
        guard !isResyncing else { return }
        for continuation in continuations.values { continuation.yield(.output(batch)) }
    }

    /// Emülatörün ızgarası değişti (SwiftTerm reflow'u yaptı).
    func sizeChanged() {
        guard hasSubscribers else { return }
        isResyncing = true
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(for: Self.resyncDelay)
            guard !Task.isCancelled else { return }
            self?.resync()
        }
    }

    private func resync() {
        isResyncing = false
        guard hasSubscribers else { return }
        let event = snapshot()
        for continuation in continuations.values { continuation.yield(event) }
    }
}
