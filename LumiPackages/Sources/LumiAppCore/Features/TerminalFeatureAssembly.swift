import Foundation
import LumiKit
import LumiState
import LumiUI

/// Terminal özelliği (refactor 3.3): prompt kuyruğu, görünüm ayarlarının canlı
/// uygulanması ve kapanışta PTY temizliği.
///
/// `.system` fazı: hiçbir spawn bu assembly'den önce olamaz — `AppContainer`
/// prelude'ünde `fixProcessPath()` koşar, sonra ilk faz burasıdır.
@MainActor
final class TerminalFeatureAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.system

    private(set) var promptQueue: PromptQueueStore!
    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
        promptQueue = PromptQueueStore(service: services.terminal, toasts: shared.toasts)
    }

    func start() async {
        let config = await services.config.config()
        applyAppearance(config)
        shared.terminals.autoMinimizeOnSend = config.autoMinimizeOnSend
        promptQueue.start()
    }

    /// Font/cursor callback dansı (eski `ConfigSideEffectCoordinator` +
    /// `AppContainer.rebuildFont` ikilisi) burada tek bloğa indi: yeni değer
    /// zaten elimizde, taze config'i yeniden okumaya gerek yok.
    func configDidChange(old: AppConfig, new: AppConfig) {
        // Aile ve boyut TEK NSFont'a birlikte çözülür — hangisi değişirse değişsin
        // font yeniden kurulur.
        if old.terminalFontFamily != new.terminalFontFamily
            || old.terminalFontSize != new.terminalFontSize {
            applyFont(new)
        }
        if old.terminalCursorStyle != new.terminalCursorStyle
            || old.terminalCursorBlink != new.terminalCursorBlink {
            applyCursor(new)
        }
        // Karar 24
        if old.autoMinimizeOnSend != new.autoMinimizeOnSend {
            shared.terminals.autoMinimizeOnSend = new.autoMinimizeOnSend
        }
    }

    func shutdown() async {
        promptQueue.stop()
        services.terminal.killAll()
        // Global NSEvent monitörleri (klavye/odak) bırakılır — sızıntı önlemi.
        services.terminal.shutdown()
    }

    // MARK: - Görünüm

    private func applyAppearance(_ config: AppConfig) {
        applyFont(config)
        applyCursor(config)
    }

    private func applyFont(_ config: AppConfig) {
        services.terminal.applyFont(LumiFonts.mono(
            family: config.terminalFontFamily,
            size: CGFloat(config.terminalFontSize)
        ))
    }

    private func applyCursor(_ config: AppConfig) {
        services.terminal.applyCursor(
            shape: TerminalCursorShape.parse(config.terminalCursorStyle),
            blink: config.terminalCursorBlink
        )
    }
}
