import AppKit
import Foundation
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// Sürüm kontrolü (karar 102) ve uygulama içi güncelleme (karar 118).
///
/// - Kontrol açılışta ve `AppUpdateStore.checkInterval`'da bir arka planda
///   koşar — bootstrap'i bloklamaz. `ContinuousClock` uykuda da ilerler;
///   uzun bir uykudan dönünce bekleyen kontrol hemen koşar.
/// - `Restart Now` kapanışı buradan başlatır (store AppKit'i görmez).
/// - Kurulum kapanış yolunda planlanır (`shutdown`): kullanıcının seçtiği
///   kurulum zamanı yoksa hiçbir şey yapılmaz.
@MainActor
final class AppUpdateFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.ui

    private(set) var appUpdate: AppUpdateStore!
    private var checkLoop: Task<Void, Never>?

    func build(services: any ServiceRegistry, shared: SharedStores) {
        appUpdate = AppUpdateStore(
            currentVersion: AppAboutInfo.current.version,
            service: services.appReleases,
            installer: services.appUpdateInstaller
        )
        let dialogs = shared.dialogs
        appUpdate.onRestartRequested = {
            dialogs.preconfirmQuit()
            // `terminate` bir main-actor işinin İÇİNDEN çağrılamaz: `.terminateLater`
            // AppKit'i `terminate`'in içinde iç içe bir run loop'a sokar, dışarıdaki
            // iş hiç bitmediği için main actor kilitlenir — `shutdownAndReply` ve
            // terminal girdisi sonsuza dek sırada kalıyordu (Lumi kapanmıyor,
            // terminaller yazı almıyordu). Run loop'un kendi zamanlayıcısından
            // çağrılınca main queue serbest kalır (⌘Q'nun menü olayıyla aynı konum).
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
    }

    func registerShellItems(into registries: ShellRegistries) {
        registries.overlays.register(OverlayDescriptor(
            id: .installUpdateDialog,
            isPresented: { $0.dialogs.installUpdateDialog != nil },
            makeView: { AnyView(InstallUpdateDialogOverlay()) }
        ))
        registries.toolbar.register(ToolbarItemDescriptor(
            id: .appUpdate,
            region: .statusTrailing,
            order: ShellToolbarItems.Order.appUpdate,
            isVisible: { $0.appUpdate.stagedUpdate != nil },
            makeView: { AnyView(AppUpdateStatusItem()) }
        ))
    }

    func start() async {
        checkLoop = Task { @MainActor [weak self] in
            await self?.appUpdate.loadInstallFailure()
            while !Task.isCancelled {
                await self?.appUpdate.check()
                try? await Task.sleep(for: AppUpdateStore.checkInterval)
            }
        }
    }

    func shutdown() async {
        checkLoop?.cancel()
        checkLoop = nil
        await appUpdate.installIfScheduled()
    }
}
