import Foundation
import LumiKit
import LumiState
import LumiTerminal

/// Repo/workspace yüklendikten SONRA anlamlı olan workspace boot durumu
/// (refactor 3.3, `.ui` fazı):
///
/// - **Onboarding kapısı:** ilk çalıştırmada sihirbaz açılır (design/03 §4).
/// - **Karar 23/80 oturum devamı:** önceki çalıştırmada persist edilen
///   Claude/Codex oturumları, açık tab'ı duran repo'larda yeniden spawn edilir. `shutdown()`
///   simetriktir ve canlı oturumları persist eder — `.ui` fazı ilk yıkılan faz
///   olduğu için persist, terminal feature'ının `killAll()`'undan ÖNCE koşar.
/// - **Karar 90 crash checkpoint'i:** aynı liste yalnız quit'te değil, canlı
///   küme her değiştiğinde (`.spawned` / `.exited` / `.codexSessionIDChanged` /
///   `.claudeSessionIDChanged`)
///   yeniden yazılır; böylece crash / SIGKILL / güç kesintisinde de son
///   snapshot diskte durur. Kapanışta tüketici ÖNCE susturulur ki `killAll()`'ın
///   `.exited`'ları son snapshot'ı boş listeyle ezmesin.
/// - **Karar 103 All Terminals sırası:** resume listesinin eşidir — aynı
///   checkpoint'te yazılır, açılışta resume spawn'larından ÖNCE geri kurulur.
@MainActor
final class WorkspaceBootAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.ui

    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!
    private var checkpointTask: Task<Void, Never>?
    /// Onboarding akışının state'i (refactor 5.8) — `RootView` bunu okur.
    private(set) var onboarding: OnboardingStore!

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
        onboarding = OnboardingStore(
            system: services.system,
            settings: shared.settings,
            toasts: shared.toasts,
            onComplete: { [weak shared] in shared?.dialogs.isOnboardingActive = false }
        )
    }

    func start() async {
        shared.dialogs.isOnboardingActive = await services.config.isFirstRun()
        await resumeAgentSessions()
        startCheckpointing()
    }

    func shutdown() async {
        checkpointTask?.cancel()
        checkpointTask = nil
        shared.terminals.onOrderChanged = nil
        // killAll'dan ÖNCE provider-owned kimlikler persist edilir. Codex'in
        // CODEX_HOME'u da thread rollout'unun bulunduğu hesapla birlikte sabitlenir.
        await checkpointResumeSessions()
    }

    /// Canlı terminallerin resume listesini `ui-state.json`'a yazar (karar 90).
    /// Debounce ve "değişmediyse yazma" `ConfigService`'tedir.
    private func checkpointResumeSessions() async {
        let live = Self.inDisplayOrder(services.terminal.terminals, order: shared.terminals.terminals)
        let resumeSessions = Self.resumeSessions(from: live)
        // Servisin canlı kümesi üzerinden: store spawn'ı henüz uygulamamış
        // olsa da yeni terminal sıranın sonunda diske iner.
        let allTerminalsOrder = shared.terminals.allArrangement.persistedKeys(live)
        await services.config.updateUIState {
            $0.resumeSessions = resumeSessions
            $0.allTerminalsOrder = allTerminalsOrder
        }
    }

    /// Terminal kümesini değiştiren her olayda snapshot yenilenir. Stream,
    /// Task'tan ÖNCE alınır (`events()` nonisolated): abonelik `start()` dönmeden
    /// kurulmuş olur.
    private func startCheckpointing() {
        guard checkpointTask == nil else { return }
        // Karar 97: elle sıralama servis olayı üretmez — sıra da diskte dursun.
        shared.terminals.onOrderChanged = { [weak self] in
            Task { @MainActor in await self?.checkpointResumeSessions() }
        }
        let stream = services.terminal.events()
        checkpointTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                guard Self.affectsResumeSessions(event) else { continue }
                await self.checkpointResumeSessions()
            }
        }
    }

    static func affectsResumeSessions(_ event: TerminalEvent) -> Bool {
        switch event {
        case .spawned, .exited, .codexSessionIDChanged, .claudeSessionIDChanged:
            return true
        case .statusChanged, .titleChanged, .providerChanged, .awaitingDecisionChanged, .bell,
             .writeFailed, .stalled, .viewFocused, .linkActivated:
            return false
        }
    }

    /// Karar 97: servis listesi spawn sırasındadır; elle sıralama yalnız
    /// store'dadır. Canlı küme store sırasına dizilir, store'a henüz
    /// yansımamış terminaller (spawn yarışı) kendi aralarındaki sırayla sona
    /// eklenir. Resume spawn'ları bu sırayla koştuğu için sıra açılışta döner.
    static func inDisplayOrder(_ live: [TerminalMeta], order: [TerminalMeta]) -> [TerminalMeta] {
        let rank = Dictionary(order.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = live
            .compactMap { meta in rank[meta.id].map { (rank: $0, meta: meta) } }
            .sorted { $0.rank < $1.rank }
            .map(\.meta)
        return known + live.filter { rank[$0.id] == nil }
    }

    static func resumeSessions(from terminals: [TerminalMeta]) -> [ResumeSession] {
        terminals.compactMap { meta in
            if meta.provider == .codex, let id = meta.codexSessionID,
               CodexSessionCommand.isSafe(id), let home = meta.codexHome {
                return ResumeSession(
                    repoPath: meta.repoPath,
                    sessionID: id,
                    provider: .codex,
                    codexHome: home
                )
            }
            guard meta.provider != .codex, let id = meta.claudeSessionID else { return nil }
            return ResumeSession(repoPath: meta.repoPath, sessionID: id)
        }
    }

    /// Kayıtlar tek seferlik tüketilir: spawn'lar bittikten sonra liste canlı
    /// terminallerden yeniden üretilir — spawn başarısız olan ya da tab'ı
    /// kapanmış repo'nun bayat kaydı sonraki açılışa sarkmaz; başarılı resume
    /// aynı kimliği taşıdığından zincir kesintisiz sürer.
    private func resumeAgentSessions() async {
        let state = await services.config.uiState()
        // Karar 103: doğacak oturumlar All Terminals'taki eski yerlerine otursun.
        shared.terminals.restoreAllArrangement(state.allTerminalsOrder)
        let entries = state.resumeSessions
        guard !entries.isEmpty else { return }
        await spawnResumedSessions(entries)
        await checkpointResumeSessions()
    }

    private func spawnResumedSessions(_ entries: [ResumeSession]) async {
        for entry in entries where shared.navigation.openTabs.contains(entry.repoPath) {
            switch entry.provider {
            case .claude:
                shared.terminals.spawn(
                    in: entry.repoPath,
                    command: ClaudeSessionCommand.resumeCommand(sessionID: entry.sessionID)
                )
            case .codex:
                let pinnedHome = await services.codexAccounts.resolvedResumeHome(entry.codexHome)
                let home = if let pinnedHome {
                    pinnedHome
                } else {
                    await services.codexAccounts.selectedHome()
                }
                let command = CodexSessionCommand.resumeCommand(sessionID: entry.sessionID) ?? "codex"
                shared.terminals.spawn(
                    in: entry.repoPath,
                    command: command,
                    environment: ["CODEX_HOME": home]
                )
            }
        }
    }
}
