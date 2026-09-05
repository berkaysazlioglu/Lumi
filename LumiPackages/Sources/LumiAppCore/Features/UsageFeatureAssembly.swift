import Foundation
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// Kullanım göstergeleri (karar 32) + otomatik tazeleme (karar 20).
@MainActor
final class UsageFeatureAssembly: FeatureAssembly, ShellContributing {
    let bootstrapPhase = BootstrapPhase.config

    private(set) var usageStores: [AgentProvider: UsageStore] = [:]
    private(set) var usageAutoRefresh: UsageAutoRefreshStore!
    private var services: (any ServiceRegistry)!
    /// Tek-atımlı ilk yükleme: her tetiklemede öncekinin yerini alır (dizide
    /// biriktirilirse sınırsız büyürdü).
    private var initialLoadTask: Task<Void, Never>?

    func build(services: any ServiceRegistry, shared: SharedStores) {
        self.services = services
        var stores: [AgentProvider: UsageStore] = [:]
        for provider in AgentProvider.allCases {
            let service = services.usage(for: provider)
            // Hangi dekoratörlerin kurulu olduğunu bilmek composition root'un
            // işidir (K38-A): `UsageServicing` cache kavramını taşımaz, store
            // da bunu kendi keşfetmeye çalışmaz.
            stores[provider] = UsageStore(
                service: service,
                cache: service as? any UsageCacheInvalidating
            )
        }
        usageStores = stores
        usageAutoRefresh = UsageAutoRefreshStore(
            stores: AgentProvider.allCases.compactMap { stores[$0] },
            activity: services.activityMonitor
        )
    }

    /// Sağlayıcı BAŞINA bir toolbar öğesi (Faz 6.4): eski
    /// `ForEach(enabledProviders)` döngüsünün yerine geçer. Ayarın açık/kapalı
    /// durumu descriptor'ın `isVisible` kapısında okunur, sıra
    /// `AgentProvider.allCases` sırasıdır (eski `enabledProviders` sırası).
    func registerShellItems(into registries: ShellRegistries) {
        for (index, provider) in AgentProvider.allCases.enumerated() {
            registries.toolbar.register(ToolbarItemDescriptor(
                id: .usageIndicator(provider),
                region: .trailing,
                order: index * ShellToolbarItems.Order.usageStep,
                isVisible: { $0.settings.current.usageIndicators.isEnabled(provider) },
                makeView: { AnyView(UsageToolbarItem(provider: provider)) }
            ))
        }
    }

    func start() async {
        let config = await services.config.config()
        applyIndicators(config.usageIndicators)
        usageAutoRefresh.configure(config.usageAutoRefresh)
        usageAutoRefresh.start()
        // İlk yükleme arka planda — bootstrap'i bloklamaz (design/05).
        scheduleInitialLoad()
    }

    func configDidChange(old: AppConfig, new: AppConfig) {
        if old.usageAutoRefresh != new.usageAutoRefresh {
            usageAutoRefresh.update(new.usageAutoRefresh)
        }
        if old.usageIndicators != new.usageIndicators {
            applyIndicators(new.usageIndicators)
            // Yeni açılan sağlayıcı boş kalmasın: kapı açıldıktan sonra ilk yükleme.
            scheduleInitialLoad()
        }
    }

    func shutdown() async {
        initialLoadTask?.cancel()
        initialLoadTask = nil
        usageAutoRefresh.stop()
    }

    // MARK: - Gösterge kapısı

    /// Config'teki açık/kapalı durumunu store'lara yansıtır. Kapı store'un
    /// içindedir: kapalı store hiçbir istek atmaz (manuel refresh dahil).
    private func applyIndicators(_ indicators: UsageIndicators) {
        for (provider, store) in usageStores {
            store.setEnabled(indicators.isEnabled(provider))
        }
    }

    private func scheduleInitialLoad() {
        initialLoadTask?.cancel()
        initialLoadTask = Task { @MainActor [weak self] in
            // Sıra `AgentProvider.allCases` ile deterministik; kapalı store'da
            // `loadInitialIfNeeded` zaten no-op'tur.
            for provider in AgentProvider.allCases {
                await self?.usageStores[provider]?.loadInitialIfNeeded()
            }
        }
    }
}
