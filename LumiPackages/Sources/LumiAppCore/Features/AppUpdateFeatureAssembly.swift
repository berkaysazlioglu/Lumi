import Foundation
import LumiKit
import LumiState
import LumiUI

/// Settings ▸ About'un sürüm kontrolü (karar 102). Açılışta bir kez, arka
/// planda sorar — bootstrap'i bloklamaz.
@MainActor
final class AppUpdateFeatureAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.ui

    private(set) var appUpdate: AppUpdateStore!
    private var launchCheck: Task<Void, Never>?

    func build(services: any ServiceRegistry, shared: SharedStores) {
        appUpdate = AppUpdateStore(
            currentVersion: AppAboutInfo.current.version,
            service: services.appReleases
        )
    }

    func start() async {
        launchCheck = Task { @MainActor [weak self] in
            await self?.appUpdate.check()
        }
    }

    func shutdown() async {
        launchCheck?.cancel()
        launchCheck = nil
    }
}
