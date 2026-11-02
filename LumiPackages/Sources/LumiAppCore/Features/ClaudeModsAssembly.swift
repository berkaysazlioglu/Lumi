import Foundation
import LumiKit
import LumiState

/// Claude modları (karar 142): Lumi'nin modlarını `~/.lumi/mods`'a kurar,
/// klasörü `ClaudeModStore`'a okur ve açık modların klasörlerini terminal
/// servisine verir — sonraki spawn'ların `CLAUDE_CODE_PLUGIN_DIRS`'i.
///
/// `.system` fazı ve listede terminal assembly'sinden ÖNCE: açılışta resume
/// edilen claude'lar da modlarıyla başlamalı (hook uç noktasıyla aynı sıra).
/// Kabuk katkısı YOK: Settings ▸ Agent sekmesi store'u `ShellContext`'ten okur.
@MainActor
final class ClaudeModsAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.system

    private(set) var store: ClaudeModStore!
    private var services: (any ServiceRegistry)!
    private var config: AppConfig = .defaults

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        store = ClaudeModStore(service: services.claudeMods, toasts: shared.toasts)
    }

    func start() async {
        config = await services.config.config()
        store.onModsChanged = { [weak self] _ in self?.pushDirectories() }
        await store.load()
        pushDirectories()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        config = new
        guard old.claudeMods != new.claudeMods else { return }
        pushDirectories()
    }

    func shutdown() async {
        store.onModsChanged = nil
    }

    private func pushDirectories() {
        services.terminal.setClaudePluginDirectories(ClaudeMods.enabledPaths(store.mods, config: config))
    }
}
