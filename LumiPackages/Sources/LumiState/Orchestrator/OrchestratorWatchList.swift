import Foundation
import LumiKit
import Observation

/// Orchestrator'ın İZLEDİĞİ Claude terminalleri (karar 103): yalnız bunların
/// bitiş / karar bekleme / hata anları özetlenip Activity'ye düşer.
///
/// Bir terminal üç yoldan listeye girer: orchestrator onu açtı
/// (`start_terminal`), ona mesaj gönderdi (`send_to_terminal`) ya da açıkça
/// izlemeye aldı (`watch_terminal`). Liste konuşmaya aittir — yeni konuşma
/// listeyi boşaltır.
///
/// Terminal kimliği yeniden açılışta değiştiği için diskte Claude oturum
/// kimlikleri tutulur (`UIState.orchestratorWatchedSessions`); açılışta bu
/// kimlikler canlı terminallere `adopt` ile yeniden bağlanır. Eşleşmeden
/// kalan kayıt (terminal geç açılabilir) korunur; liste `capacity` ile
/// sınırlı olduğundan geri gelmeyenler zamanla düşer.
@Observable
@MainActor
public final class OrchestratorWatchList {
    /// Diske yazılan liste bu kadarla sınırlı (en yeniler kalır).
    public static let capacity = 50

    /// İzlenen canlı terminaller, eklenme sırasıyla.
    public private(set) var terminalIDs: [TerminalID] = []
    /// Diskten okunup henüz canlı bir terminale bağlanmamış oturumlar.
    private(set) var restoredSessions: [String] = []

    @ObservationIgnored private var sessions: [TerminalID: String] = [:]
    @ObservationIgnored private let config: (any ConfigServicing)?
    /// Yazımlar sırayla diske insin.
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    public init(config: (any ConfigServicing)? = nil) {
        self.config = config
    }

    /// İzleniyor mu? Saf sorgu (view'dan çağrılabilir): diskten gelen ama
    /// henüz bağlanmamış oturumu da sayar.
    public func isWatched(_ meta: TerminalMeta) -> Bool {
        if terminalIDs.contains(meta.id) { return true }
        guard let session = meta.claudeSessionID else { return false }
        return restoredSessions.contains(session)
    }

    /// İzlemeye alır; zaten izleniyorsa false.
    @discardableResult
    public func watch(_ meta: TerminalMeta) -> Bool {
        adopt(meta)
        guard !terminalIDs.contains(meta.id) else { return false }
        terminalIDs.append(meta.id)
        sessions[meta.id] = meta.claudeSessionID
        persist()
        return true
    }

    /// İzlemeyi bırakır; izlenmiyorsa false.
    @discardableResult
    public func unwatch(_ meta: TerminalMeta) -> Bool {
        adopt(meta)
        guard let index = terminalIDs.firstIndex(of: meta.id) else { return false }
        terminalIDs.remove(at: index)
        sessions[meta.id] = nil
        persist()
        return true
    }

    /// Yeni konuşma: model eski listeyi bilmez.
    public func clear() {
        guard !terminalIDs.isEmpty || !restoredSessions.isEmpty else { return }
        terminalIDs = []
        sessions = [:]
        restoredSessions = []
        persist()
    }

    // MARK: - Terminal olayları

    /// Diskten gelen oturum bu terminale aitse terminal kimliğine bağlanır.
    public func adopt(_ meta: TerminalMeta) {
        guard let session = meta.claudeSessionID, let index = restoredSessions.firstIndex(of: session) else { return }
        restoredSessions.remove(at: index)
        if !terminalIDs.contains(meta.id) { terminalIDs.append(meta.id) }
        sessions[meta.id] = session
    }

    /// `/clear` sonrası oturum kimliği değişti (karar 94): kalıcı kayıt izlesin.
    public func sessionChanged(_ id: TerminalID, to session: String) {
        guard terminalIDs.contains(id), sessions[id] != session else { return }
        sessions[id] = session
        persist()
    }

    /// Terminal kapandı: canlı listeden düşer. Diske YAZILMAZ — quit'te tüm
    /// terminaller kapanır ve liste bir sonraki açılışta geri gelmelidir.
    public func forget(_ id: TerminalID) {
        guard let index = terminalIDs.firstIndex(of: id) else { return }
        terminalIDs.remove(at: index)
        sessions[id] = nil
    }

    // MARK: - Kalıcılık

    /// Diskteki listeyi okur ve hâlihazırda açık terminallere bağlar.
    public func load(matching terminals: [TerminalMeta]) async {
        guard let config else { return }
        let stored = await config.uiState().orchestratorWatchedSessions ?? []
        let known = Set(sessions.values)
        restoredSessions = stored.filter { !known.contains($0) }
        terminals.forEach(adopt)
    }

    /// Bekleyen yazımları tamamlar (testler ve shutdown).
    public func flush() async {
        await persistTask?.value
    }

    private func persist() {
        guard let config else { return }
        let snapshot = Array((terminalIDs.compactMap { sessions[$0] } + restoredSessions).suffix(Self.capacity))
        let previous = persistTask
        persistTask = Task {
            await previous?.value
            await config.updateUIState { $0.orchestratorWatchedSessions = snapshot }
        }
    }
}
