import Foundation
import LumiKit
import LumiState

/// Zamanlanmış oturum tetikleyicisi (refactor 3.3). Tek store, tek config alanı.
@MainActor
final class SessionScheduleAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.config

    private(set) var sessionSchedule: SessionScheduleStore!
    private var services: (any ServiceRegistry)!

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        sessionSchedule = SessionScheduleStore(starter: services.sessionStarter)
    }

    func start() async {
        let config = await services.config.config()
        // configure → start: ayar saklanır, zamanlama `StoreLifecycle` ile kurulur.
        sessionSchedule.configure(config.sessionTrigger)
        sessionSchedule.start()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        guard old.sessionTrigger != new.sessionTrigger else { return }
        sessionSchedule.update(new.sessionTrigger)
    }

    func shutdown() async {
        sessionSchedule.stop()
    }
}
