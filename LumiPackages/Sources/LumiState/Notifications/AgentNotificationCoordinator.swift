import Foundation
import LumiKit

/// Ajan terminallerinin bildirim anlarını yakalar (karar 145, Orca paritesi).
///
/// - **Tur başına bir bildirim.** Bildirim yalnız gerçek bir kenarda doğar:
///   `working` → `waiting*` (bitti), `working` → `error` (hata) ve karar
///   beklemenin başlaması. Boşta duran, görülmüş ya da hiç çalışmamış chat
///   kenar üretmez — tekrar hatırlatma yoktur.
/// - **Oturma süresi.** Claude alt ajan / compaction sırasında kısa süre
///   `waiting`'e düşüp geri dönebilir; olay `settleDelay` boyunca geçerli
///   kalırsa üretilir. Yeni `working`, karar çözülmesi ya da kesme
///   (`interruptInferred` — kullanıcı turu kendisi durdurdu) bekleyeni iptal eder.
/// - **Görüldü.** Terminal yeniden çalışınca ya da odakta beklerken teslim
///   edilmiş bildirimi Notification Center'dan kalkar.
/// - **İçerik.** Chat adı, checkout ve ajanın son mesajı (`AgentNotificationText`).
///
/// Teslim kuralları (ayarlar, pencere odağı, bekleme süresi)
/// `NotificationServicing`'dedir.
@MainActor
public final class AgentNotificationCoordinator {
    public static let defaultSettleDelay: Duration = .milliseconds(1500)

    private let service: any TerminalSessionControlling
    private let terminals: TerminalListStore
    private let notifications: any NotificationServicing
    private let transcripts: any TerminalTranscriptReading
    private let checkoutLabel: @MainActor (String) -> String
    private let settleDelay: Duration
    private let consumer = EventConsumer(label: "agentNotifications")

    private var statuses: [TerminalID: TerminalStatus] = [:]
    private var pending: [TerminalID: Pending] = [:]
    private var generation = 0

    private struct Pending {
        let kind: AgentNotification.Kind
        let generation: Int
        let task: Task<Void, Never>
    }

    public init(
        service: any TerminalSessionControlling,
        terminals: TerminalListStore,
        notifications: any NotificationServicing,
        transcripts: any TerminalTranscriptReading,
        checkoutLabel: @escaping @MainActor (String) -> String,
        settleDelay: Duration = AgentNotificationCoordinator.defaultSettleDelay
    ) {
        self.service = service
        self.terminals = terminals
        self.notifications = notifications
        self.transcripts = transcripts
        self.checkoutLabel = checkoutLabel
        self.settleDelay = settleDelay
    }

    public func start() {
        consumer.start(service.events()) { [weak self] event in
            self?.apply(event)
        }
    }

    public func stop() {
        consumer.stop()
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll()
    }

    // MARK: - Olaylar (testler doğrudan sürer)

    func apply(_ event: TerminalEvent) {
        switch event {
        case .statusChanged(let id, let status):
            applyStatus(id, status)
        case .awaitingDecisionChanged(let id, let awaiting):
            if awaiting {
                schedule(id, .needsInput)
            } else if pending[id]?.kind == .needsInput {
                cancel(id)
            }
        case .interruptInferred(let id):
            cancel(id)
        case .exited(let id, _):
            cancel(id)
            statuses[id] = nil
            notifications.terminalRemoved(id)
        case .spawned, .titleChanged, .providerChanged, .codexSessionIDChanged, .claudeSessionIDChanged,
             .claudeLaunchArgumentsChanged, .bell, .writeFailed, .viewFocused, .stalled, .linkActivated:
            break
        }
    }

    private func applyStatus(_ id: TerminalID, _ status: TerminalStatus) {
        let previous = statuses[id]
        statuses[id] = status
        switch status {
        case .working:
            cancel(id)
            notifications.dismiss(id)
        case .waitingUnseen, .waitingSeen, .waitingFocused:
            if previous == .working { schedule(id, .finished) }
            if status == .waitingFocused { notifications.dismiss(id) }
        case .error:
            if previous == .working { schedule(id, .failed) }
        case .idle:
            cancel(id)
            notifications.dismiss(id)
        }
    }

    private func schedule(_ id: TerminalID, _ kind: AgentNotification.Kind) {
        cancel(id)
        generation += 1
        let current = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.settleDelay)
            guard !Task.isCancelled else { return }
            await self.produce(id, kind, generation: current)
        }
        pending[id] = Pending(kind: kind, generation: current, task: task)
    }

    private func cancel(_ id: TerminalID) {
        pending.removeValue(forKey: id)?.task.cancel()
    }

    /// Bekleyen olay hâlâ bu kuşak mı ve durum hâlâ geçerli mi?
    private func isStillCurrent(_ id: TerminalID, _ kind: AgentNotification.Kind, generation: Int) -> Bool {
        guard pending[id]?.generation == generation else { return false }
        switch kind {
        case .finished: return statuses[id]?.isWaiting == true
        case .failed: return statuses[id] == .error
        case .needsInput: return terminals.awaitingDecisionIDs.contains(id)
        }
    }

    private func produce(_ id: TerminalID, _ kind: AgentNotification.Kind, generation: Int) async {
        guard isStillCurrent(id, kind, generation: generation), let meta = terminals.meta(for: id) else { return }
        let lastMessage = kind == .needsInput ? nil : await transcripts.lastClaudeAssistantText(of: meta)
        // Transkript okunurken yeni tur başlamış ya da kesilmiş olabilir.
        guard isStillCurrent(id, kind, generation: generation) else { return }
        pending[id] = nil
        let latest = terminals.meta(for: id) ?? meta
        notifications.deliver(AgentNotification(
            terminalID: id,
            kind: kind,
            title: AgentNotificationText.title(displayTitle: latest.displayTitle, provider: latest.provider),
            subtitle: AgentNotificationText.subtitle(
                checkout: checkoutLabel(latest.repoPath), provider: latest.provider, kind: kind
            ),
            body: AgentNotificationText.body(kind: kind, lastMessage: lastMessage, provider: latest.provider),
            isTerminalFocused: isTerminalFocused(id, kind),
            groupKey: latest.repoPath
        ))
    }

    /// Bitişte durum makinesinin kendi odak hükmü (`waitingFocused` = turn
    /// kapandığında terminal odakta ve pencere öndeydi) geçerlidir; diğer
    /// durumlarda store'un aktif terminali. Pencere odağını servis ekler.
    private func isTerminalFocused(_ id: TerminalID, _ kind: AgentNotification.Kind) -> Bool {
        if kind == .finished { return statuses[id] == .waitingFocused }
        return terminals.isFocusedOnSurface(id)
    }
}
