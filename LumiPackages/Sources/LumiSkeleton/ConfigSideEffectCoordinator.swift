import Foundation
import LumiKit

/// Config yan etki propagasyonu (design/02 §2, karar 3'ün altyapısı).
/// Alanlar EŞİTLİKLE karşılaştırılır — Electron'un truthiness bug'ı (0/boş
/// string yan etkiyi atlardı, karar 11) yapısal olarak imkânsız.
@MainActor
final class ConfigSideEffectCoordinator {
    private let config: any ConfigServicing
    private let terminal: any TerminalServicing
    private var consumeTask: Task<Void, Never>?

    init(config: any ConfigServicing, terminal: any TerminalServicing) {
        self.config = config
        self.terminal = terminal
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [config, terminal] in
            let stream = await config.events()
            for await event in stream {
                guard case .configChanged(let old, let new) = event else { continue }
                if old.maxTerminals != new.maxTerminals {
                    terminal.setMaxTerminals(new.maxTerminals)
                }
                // projectsRoot/additionalPaths → RepoService (Faz 3)
                // notifications → NotificationService (Faz 3)
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }
}
