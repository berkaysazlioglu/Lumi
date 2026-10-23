import Foundation
import LumiKit
import LumiState
import os

/// Ajan hook köprüsü (karar 45): loopback sunucuyu açar, uç noktayı terminal
/// servisine verir (sonraki spawn'ların env'i), Claude/Codex ayar dosyalarına
/// yönetilen hook'ları kurar ve gelen olayları oturumlara akıtır.
///
/// `.system` fazı ve listede terminal assembly'sinden ÖNCE: ilk spawn (workspace
/// restore) uç noktayı env'inde bulmalı; aksi halde o terminalin ajanı hook
/// yollayamaz ve kart sezgisel yola düşer.
@MainActor
final class AgentHooksAssembly: FeatureAssembly {
    /// Teşhis izi (karar 83).
    private static let logger = LumiLog.logger("agentHooks")
    let bootstrapPhase = BootstrapPhase.system

    private var services: (any ServiceRegistry)!
    private var shared: SharedStores!
    private var ingest: Task<Void, Never>?
    private(set) var isEnabled = false

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        self.shared = shared
    }

    func start() async {
        let config = await services.config.config()
        guard config.agentHooksEnabled else { return }
        await enable()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        guard old.agentHooksEnabled != new.agentHooksEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if new.agentHooksEnabled {
                await self.enable()
            } else {
                await self.disable(uninstall: true)
            }
        }
    }

    func shutdown() async {
        // Kapanışta hook'lar yerinde kalır (Orca ile aynı): sonraki açılış aynı
        // girdileri bulur; sunucu yokken script `curl` hatasıyla anında döner.
        await disable(uninstall: false)
    }

    // MARK: - Aç / kapa

    private func enable() async {
        guard !isEnabled else { return }
        do {
            let endpoint = try await services.agentHooks.start()
            services.terminal.setAgentHookEndpoint(endpoint)
            // Karar 123: orchestrator Codex'i thread kimliğini ve durumunu hook'tan bildirir.
            services.orchestratorTerminal.setAgentHookEndpoint(endpoint)
        } catch {
            shared.toasts.show(
                .error,
                title: "Agent hooks",
                message: "Hook server could not start: \(error.localizedDescription)"
            )
            return
        }
        isEnabled = true
        startIngest()
        // Later UI-phase account sync may mirror Codex hooks into isolated
        // homes, so installation must finish before bootstrap advances.
        report(await services.agentHookInstaller.install())
        await services.codexAccounts.syncManagedHooks(enabled: true)
    }

    private func disable(uninstall: Bool) async {
        Self.logger.log("disable(uninstall: \(uninstall)) enabled=\(self.isEnabled)")
        ingest?.cancel()
        ingest = nil
        guard isEnabled else { return }
        isEnabled = false
        services.terminal.setAgentHookEndpoint(nil)
        services.orchestratorTerminal.setAgentHookEndpoint(nil)
        await services.agentHooks.stop()
        if uninstall {
            let results = await services.agentHookInstaller.uninstall()
            report(results)
            await services.codexAccounts.syncManagedHooks(enabled: false)
        }
    }

    private func startIngest() {
        guard ingest == nil else { return }
        let stream = services.agentHooks.events()
        Self.logger.log("ingest start")
        ingest = Task { @MainActor [weak self] in
            var handled = 0
            for await event in stream {
                guard let self else { return }
                // Her yönetici yalnız kendi terminalini tanır; diğeri olayı düşürür.
                self.services.terminal.applyAgentHookEvent(event)
                self.services.orchestratorTerminal.applyAgentHookEvent(event)
                handled += 1
            }
            Self.logger.log("ingest loop ended (cancelled: \(Task.isCancelled), handled \(handled))")
        }
    }

    /// Yalnız hatalar kullanıcıya gösterilir; kurulum/atlama sessizdir.
    private func report(_ results: [AgentHookInstallResult]) {
        for result in results {
            if case .failed(let detail) = result.outcome {
                shared.toasts.show(
                    .error,
                    title: "\(result.provider.rawValue.capitalized) hooks",
                    message: "Could not update hook settings: \(detail)"
                )
            }
        }
    }
}
