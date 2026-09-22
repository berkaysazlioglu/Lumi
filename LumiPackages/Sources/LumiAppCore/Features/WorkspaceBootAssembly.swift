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
///   küme her değiştiğinde (`.spawned` / `.exited` / `.codexSessionIDChanged`)
///   yeniden yazılır; böylece crash / SIGKILL / güç kesintisinde de son
///   snapshot diskte durur. Kapanışta tüketici ÖNCE susturulur ki `killAll()`'ın
///   `.exited`'ları son snapshot'ı boş listeyle ezmesin.
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
        // killAll'dan ÖNCE provider-owned kimlikler persist edilir. Codex'in
        // CODEX_HOME'u da thread rollout'unun bulunduğu hesapla birlikte sabitlenir.
        await checkpointResumeSessions()
    }

    /// Canlı terminallerin resume listesini `ui-state.json`'a yazar (karar 90).
    /// Debounce ve "değişmediyse yazma" `ConfigService`'tedir.
    private func checkpointResumeSessions() async {
        let resumeSessions = Self.resumeSessions(from: services.terminal.terminals)
        await services.config.updateUIState { $0.resumeSessions = resumeSessions }
    }

    /// Terminal kümesini değiştiren her olayda snapshot yenilenir. Stream,
    /// Task'tan ÖNCE alınır (`events()` nonisolated): abonelik `start()` dönmeden
    /// kurulmuş olur.
    private func startCheckpointing() {
        guard checkpointTask == nil else { return }
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
        case .spawned, .exited, .codexSessionIDChanged:
            return true
        case .statusChanged, .titleChanged, .providerChanged, .awaitingDecisionChanged, .bell,
             .writeFailed, .stalled, .viewFocused, .linkActivated:
            return false
        }
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
        let entries = await services.config.uiState().resumeSessions
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
