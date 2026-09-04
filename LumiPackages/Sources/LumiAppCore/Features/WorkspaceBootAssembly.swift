import Foundation
import LumiKit
import LumiState
import LumiTerminal

/// Repo/workspace yüklendikten SONRA anlamlı olan workspace boot durumu
/// (refactor 3.3, `.ui` fazı):
///
/// - **Onboarding kapısı:** ilk çalıştırmada sihirbaz açılır (design/03 §4).
/// - **Karar 23 oturum devamı:** önceki graceful quit'te persist edilen claude
///   oturumları, açık tab'ı duran repo'larda yeniden spawn edilir. `shutdown()`
///   simetriktir ve canlı oturumları persist eder — `.ui` fazı ilk yıkılan faz
///   olduğu için persist, terminal feature'ının `killAll()`'undan ÖNCE koşar.
@MainActor
final class WorkspaceBootAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.ui

    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
    }

    func start() async {
        shared.workspace.isOnboardingActive = await services.config.isFirstRun()
        await resumeClaudeSessions()
    }

    func shutdown() async {
        // Karar 23: killAll'dan ÖNCE canlı claude oturumları persist edilir —
        // bir sonraki açılış aynı chat'lerden devam eder. Graceful /exit gerekmez:
        // transcript kill sonrası da sağlamdır (ampirik doğrulama karar 23'te).
        let resumeSessions = services.terminal.terminals.compactMap { meta in
            meta.claudeSessionID.map {
                ResumeSession(repoPath: meta.repoPath, sessionID: $0)
            }
        }
        await services.config.updateUIState { $0.resumeSessions = resumeSessions }
    }

    /// Kayıtlar TEK SEFERLİK tüketilir (önce boşaltılır — spawn başarısız olsa
    /// bile bayat liste sonraki açılışlara sarkmaz).
    private func resumeClaudeSessions() async {
        let entries = await services.config.uiState().resumeSessions
        guard !entries.isEmpty else { return }
        await services.config.updateUIState { $0.resumeSessions = [] }
        for entry in entries where shared.workspace.openTabs.contains(entry.repoPath) {
            shared.terminals.spawn(
                in: entry.repoPath,
                command: ClaudeSessionCommand.resumeCommand(sessionID: entry.sessionID)
            )
        }
    }
}
