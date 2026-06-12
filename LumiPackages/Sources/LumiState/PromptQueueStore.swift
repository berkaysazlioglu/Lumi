import Foundation
import LumiKit
import Observation

/// Terminal başına prompt kuyruğu (kullanıcının ardarda dizdiği prompt'lar).
/// Agent bir turn'ü bitirip "bekliyor"a geçince — durum kısa süre stabil kalırsa
/// ve "karar bekliyor" (izin promptu) değilse ve kuyruk duraklatılmamışsa —
/// sıradaki prompt bracketed-paste ile enjekte edilir.
///
/// Tasarım: status/izin sinyallerini servis event akışından kendi izler
/// (self-contained), yazımı `TerminalServicing.write` hunisinden yapar.
/// "Bekliyor" ile "karar bekliyor"u ayırmak kritik — ikincisinde araya prompt
/// sokmak, Claude'un sorusunu yanlış cevaplamak demektir.
@Observable
@MainActor
public final class PromptQueueStore {
    public private(set) var queues: [TerminalID: [String]] = [:]
    public private(set) var pausedIDs: Set<TerminalID> = []

    @ObservationIgnored private let service: any TerminalServicing
    @ObservationIgnored private let settleDelay: Duration
    @ObservationIgnored private var statuses: [TerminalID: TerminalStatus] = [:]
    @ObservationIgnored private var awaitingDecisionIDs: Set<TerminalID> = []
    @ObservationIgnored private var settleTasks: [TerminalID: Task<Void, Never>] = [:]
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    /// Bekleme durumunun stabil sayılması için geçmesi gereken süre — anlık
    /// flicker'a ve kullanıcıya manuel müdahale aralığı tanımak için.
    public init(service: any TerminalServicing, settleDelay: Duration = .milliseconds(1500)) {
        self.service = service
        self.settleDelay = settleDelay
    }

    public func start() {
        guard consumeTask == nil else { return }
        let stream = service.events()
        consumeTask = Task { @MainActor [weak self] in
            for await event in stream {
                self?.apply(event)
            }
        }
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
        for task in settleTasks.values { task.cancel() }
        settleTasks.removeAll()
    }

    // MARK: - Sorgular

    public func prompts(for id: TerminalID) -> [String] {
        queues[id] ?? []
    }

    public func count(for id: TerminalID) -> Int {
        queues[id]?.count ?? 0
    }

    public func isPaused(_ id: TerminalID) -> Bool {
        pausedIDs.contains(id)
    }

    // MARK: - Kuyruk düzenleme (immutable kopya ile)

    public func enqueue(_ prompt: String, for id: TerminalID) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var queue = queues[id] ?? []
        queue.append(trimmed)
        queues[id] = queue
        reevaluate(id)
    }

    public func remove(at index: Int, for id: TerminalID) {
        guard var queue = queues[id], queue.indices.contains(index) else { return }
        queue.remove(at: index)
        queues[id] = queue
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int, for id: TerminalID) {
        guard var queue = queues[id] else { return }
        // SwiftUI'ya bağlanmadan onMove semantiği: taşınanları çıkar, hedefe ekle.
        let moved = source.sorted().map { queue[$0] }
        for index in source.sorted(by: >) {
            queue.remove(at: index)
        }
        let insertAt = destination - source.filter { $0 < destination }.count
        queue.insert(contentsOf: moved, at: max(0, min(insertAt, queue.count)))
        queues[id] = queue
    }

    public func clear(for id: TerminalID) {
        queues[id] = []
        cancelSettle(id)
    }

    public func setPaused(_ paused: Bool, for id: TerminalID) {
        if paused {
            pausedIDs.insert(id)
            cancelSettle(id)
        } else {
            pausedIDs.remove(id)
            reevaluate(id)
        }
    }

    // MARK: - Event uygulama (testler doğrudan sürebilsin diye internal)

    func apply(_ event: TerminalEvent) {
        switch event {
        case .statusChanged(let id, let status):
            statuses[id] = status
            reevaluate(id)
        case .awaitingDecisionChanged(let id, let awaiting):
            if awaiting {
                awaitingDecisionIDs.insert(id)
            } else {
                awaitingDecisionIDs.remove(id)
            }
            reevaluate(id)
        case .exited(let id, _):
            queues[id] = nil
            pausedIDs.remove(id)
            statuses[id] = nil
            awaitingDecisionIDs.remove(id)
            cancelSettle(id)
        case .spawned, .titleChanged, .bell:
            break
        }
    }

    /// Enjeksiyon için tüm koşullar sağlanıyor mu (saf predikat).
    func canInject(_ id: TerminalID) -> Bool {
        guard let queue = queues[id], !queue.isEmpty else { return false }
        guard !pausedIDs.contains(id) else { return false }
        guard !awaitingDecisionIDs.contains(id) else { return false }
        return statuses[id]?.isWaiting == true
    }

    // MARK: - Tetikleme

    private func reevaluate(_ id: TerminalID) {
        cancelSettle(id)
        guard canInject(id) else { return }
        settleTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.settleDelay)
            guard !Task.isCancelled, self.canInject(id) else { return }
            self.injectHead(id)
        }
    }

    /// Kuyruğun başındaki prompt'u enjekte eder; başarısız yazımda kuyruk korunur.
    func injectHead(_ id: TerminalID) {
        guard var queue = queues[id], let prompt = queue.first else { return }
        do {
            try service.write(id: id, text: PromptInjection.encode(prompt))
            queue.removeFirst()
            queues[id] = queue
        } catch {
            // Yazım başarısız: prompt kuyrukta kalır, sonraki bekleme'de tekrar denenir.
        }
    }

    private func cancelSettle(_ id: TerminalID) {
        settleTasks[id]?.cancel()
        settleTasks[id] = nil
    }

    /// Test yardımcısı: bekleyen enjeksiyon görevini await etmek için.
    func pendingInjection(for id: TerminalID) -> Task<Void, Never>? {
        settleTasks[id]
    }
}
