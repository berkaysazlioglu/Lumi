import Foundation
import LumiKit
import LumiState

/// Composition root'un koşucusu (design/00 §3, refactor 3.3).
///
/// **Hiçbir feature'ı tanımaz.** Yaptığı iş:
/// 1. Prelude — dizinler + `fixProcessPath()` (HER spawn'dan ve check'ten önce),
/// 2. paylaşılan store'ların yaşam döngüsü,
/// 3. assembly'leri `BootstrapPhase` sırasında `start()`,
/// 4. config yan etkilerini koordinatöre bağlamak,
/// 5. `shutdown()`'da hepsinin simetrik yıkımı.
///
/// Yeni özellik eklemek bu dosyaya DOKUNMAZ — composition listesine bir satır.
@MainActor
final class AppContainer {
    let services: any ServiceRegistry
    let shared: SharedStores

    /// Faz sırasına göre sabitlenmiş liste (stabil sıralama: aynı fazdakiler
    /// kayıt sırasını korur).
    private let assemblies: [any FeatureAssembly]
    private let configCoordinator: ConfigSideEffectCoordinator
    /// Refactor 3.13: uçuştaki bootstrap. `shutdown()` önce bunu iptal edip
    /// bekler — yarım kurulmuş bir graf üzerinde yıkım koşmaz.
    private var startTask: Task<Void, Never>?
    private var didStart = false

    init(
        services: any ServiceRegistry,
        shared: SharedStores,
        assemblies: [any FeatureAssembly]
    ) {
        self.services = services
        self.shared = shared
        self.assemblies = assemblies.enumerated()
            .sorted { lhs, rhs in
                lhs.element.bootstrapPhase == rhs.element.bootstrapPhase
                    ? lhs.offset < rhs.offset
                    : lhs.element.bootstrapPhase < rhs.element.bootstrapPhase
            }
            .map(\.element)
        configCoordinator = ConfigSideEffectCoordinator(config: services.config)
        for assembly in self.assemblies {
            assembly.build(services: services, shared: shared)
            configCoordinator.register(assembly)
        }
    }

    /// Idempotent: ikinci çağrı uçuştaki (ya da bitmiş) bootstrap'i bekler.
    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runBootstrap()
        }
        startTask = task
        await task.value
    }

    private func runBootstrap() async {
        guard !didStart else { return }
        didStart = true

        do {
            try services.paths.ensureDirectoriesExist()
        } catch {
            shared.toasts.show(error: .configIOFailed(
                file: services.paths.configDir.path,
                detail: error.localizedDescription
            ))
        }

        // design/00 §3: her PTY spawn'ından ve SystemChecker'dan ÖNCE.
        await services.system.fixProcessPath()
        if Task.isCancelled { return }

        await shared.start()

        for assembly in assemblies {
            if Task.isCancelled { return }
            await assembly.start()
        }

        configCoordinator.start()
    }

    func shutdown() async {
        // Refactor 3.13: uçuştaki bootstrap'i durdur ve BİTMESİNİ bekle.
        startTask?.cancel()
        await startTask?.value
        startTask = nil

        configCoordinator.stop()
        // Paylaşılan tüketiciler ÖNCE susar: aşağıdaki `killAll()`'ın ürettiği
        // `.exited` event'leri kapanış anında toast doğurmasın.
        shared.stop()
        for assembly in assemblies.reversed() {
            await assembly.shutdown()
        }
        await services.config.flushPendingWrites()
        // Temp dizini (Electron will-quit paritesi + karar 11)
        try? FileManager.default.removeItem(at: services.paths.tempDir)
    }

    func defaultRepoPath() async -> String {
        let config = await services.config.config()
        return config.projectsRoot.isEmpty ? NSHomeDirectory() : config.projectsRoot
    }
}
