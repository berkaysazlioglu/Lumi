import Foundation
import LumiKit
import LumiServices
import LumiState
import LumiTerminal

/// Composition root (design/00 §3). Tüm servisler ve store'lar burada, protokol
/// tipleriyle BİR KEZ inşa edilir; somut tipleri yalnız bu hedef tanır.
/// Gerçek app target'a taşınana dek skeleton'da yaşar.
@MainActor
final class AppContainer {
    let paths: LumiPaths
    let config: any ConfigServicing
    let system: any SystemServicing
    let terminal: TerminalSessionManager
    let toasts: ToastStore
    let terminals: TerminalListStore
    let configCoordinator: ConfigSideEffectCoordinator

    init() {
        #if DEBUG
        let mode = LumiPaths.Mode.development
        #else
        let mode = LumiPaths.Mode.production
        #endif
        paths = LumiPaths(mode: mode)
        config = ConfigService(paths: paths)
        system = SystemService(smokeTester: PTYSmokeTester())
        terminal = TerminalSessionManager()
        toasts = ToastStore()
        terminals = TerminalListStore(service: terminal, toasts: toasts)
        configCoordinator = ConfigSideEffectCoordinator(config: config, terminal: terminal)
    }

    /// Sıra-bağımlı bootstrap (design/00 §3): dizinler → fixProcessPath
    /// (her spawn'dan ÖNCE) → config'in anlık değerleri → store/koordinatör start.
    func start() async {
        do {
            try paths.ensureDirectoriesExist()
        } catch {
            toasts.show(error: .configIOFailed(
                file: paths.configDir.path,
                detail: error.localizedDescription
            ))
        }

        await system.fixProcessPath()

        let appConfig = await config.config()
        terminal.setMaxTerminals(appConfig.maxTerminals)

        terminals.start()
        configCoordinator.start()
    }

    func defaultRepoPath() async -> String {
        let appConfig = await config.config()
        return appConfig.projectsRoot.isEmpty ? NSHomeDirectory() : appConfig.projectsRoot
    }

    func shutdown() async {
        terminal.killAll()
        await config.flushPendingWrites()
    }
}
