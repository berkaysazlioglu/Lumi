import Foundation
import LumiKit
import OSLog

/// Orchestrator'ın teslim adresi: çalışan Codex oturumunun thread'i ve o
/// oturumun açıldığı `CODEX_HOME` (`codex queue` aynı hesapta koşmalı).
public struct OrchestratorDeliveryTarget: Equatable, Sendable {
    public let thread: String
    public let codexHome: String?

    public init(thread: String, codexHome: String?) {
        self.thread = thread
        self.codexHome = codexHome
    }
}

/// Monitoring (karar 123 Faz 2): terminal olaylarını DEĞİL, haiku özetlerinin
/// toplandığı yeri (`OrchestratorActivityFeed`) dinler. Yeni özet gelince
/// raporlanmamış olayları tek `<lumi-activity>` notu yapıp `codex queue` ile
/// çalışan orchestrator oturumuna bırakır — Codex boşalınca notu alır ve
/// kullanıcı bir şey demeden raporlar. Kuyruk kullanıcının composer'daki
/// yarım taslağına dokunmaz.
///
/// - **Toplama:** aynı anda biten terminaller tek nota girsin diye teslim
///   `batchDelay` kadar ertelenir.
/// - **Hedef yoksa** (Codex kapalı, kurulumda ya da thread'ini henüz
///   bildirmedi) olaylar feed'de bekler; hedef gelince (`targetBecameAvailable`)
///   gönderilir.
/// - **Hata:** teslim edilemeyen olaylar feed'e geri döner; bir sonraki özet
///   ya da hedef değişimi yeniden dener (sonsuz yeniden deneme döngüsü yok).
@MainActor
public final class OrchestratorActivityMonitor {
    public static let defaultBatchDelay: Duration = .seconds(1)
    private static let logger = LumiLog.logger("orchestratorMonitor")

    /// Son teslim hatası (teşhis); başarılı teslimde temizlenir.
    public private(set) var lastError: String?

    private let feed: OrchestratorActivityFeed
    private let launcher: any OrchestratorLaunching
    private let target: @MainActor () -> OrchestratorDeliveryTarget?
    private let batchDelay: Duration
    private let now: @MainActor () -> Date
    private var flushTask: Task<Void, Never>?
    private var isDelivering = false
    /// Karar 126: özetler Codex'e bırakıldı — terminallerden orchestrator'a ışık.
    public var onDelivered: (@MainActor ([OrchestratorEvent]) -> Void)?

    public init(
        feed: OrchestratorActivityFeed,
        launcher: any OrchestratorLaunching,
        target: @escaping @MainActor () -> OrchestratorDeliveryTarget?,
        batchDelay: Duration = OrchestratorActivityMonitor.defaultBatchDelay,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.feed = feed
        self.launcher = launcher
        self.target = target
        self.batchDelay = batchDelay
        self.now = now
    }

    public func start() {
        feed.onAppend = { [weak self] in self?.scheduleFlush() }
    }

    public func stop() {
        feed.onAppend = nil
        flushTask?.cancel()
        flushTask = nil
    }

    /// Orchestrator thread'ini bildirdi: bekleyen olaylar gönderilsin.
    public func targetBecameAvailable() {
        scheduleFlush()
    }

    // MARK: - Teslim

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self, batchDelay] in
            try? await Task.sleep(for: batchDelay)
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            await self.flush()
        }
    }

    /// Testler doğrudan sürer.
    func flush() async {
        guard !isDelivering, feed.hasUnreported, let target = target() else { return }
        isDelivering = true
        defer { isDelivering = false }
        let events = feed.takeUnreported()
        let note = OrchestratorActivityNote.make(events, now: now())
        do {
            try await launcher.queue(note, thread: target.thread, codexHome: target.codexHome)
            lastError = nil
            Self.logger.log("queued \(events.count) update(s) to the orchestrator")
            onDelivered?(events)
        } catch {
            feed.returnUnreported(events)
            lastError = (error as? LumiError)?.errorDescription ?? error.localizedDescription
            Self.logger.error("queue failed: \(self.lastError ?? "-", privacy: .public)")
            return
        }
        // Teslim sürerken yeni özet geldiyse o da gitsin.
        if feed.hasUnreported { scheduleFlush() }
    }
}
