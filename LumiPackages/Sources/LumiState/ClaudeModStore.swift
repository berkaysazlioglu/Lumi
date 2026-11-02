import Foundation
import LumiKit
import Observation

/// Settings ▸ Agent ▸ Claude Mods (karar 142): mod klasöründeki modların
/// listesi. Açık/kapalı durumu config'dedir (`AppConfig.claudeMods`,
/// `SettingsStore.setClaudeModEnabled`); store yalnız diskte ne olduğunu taşır.
@Observable
@MainActor
public final class ClaudeModStore {
    @ObservationIgnored private let service: any ClaudeModServicing
    @ObservationIgnored private let toasts: ToastStore?
    /// Liste değişince (yükleme, yeniden tarama) — terminal kanalı yeniden
    /// beslensin diye assembly bağlar.
    @ObservationIgnored public var onModsChanged: (@MainActor ([ClaudeMod]) -> Void)?

    public private(set) var mods: [ClaudeMod] = []

    public init(service: any ClaudeModServicing = EmptyClaudeModService(), toasts: ToastStore? = nil) {
        self.service = service
        self.toasts = toasts
    }

    public var directory: String { service.directory }

    /// Açılışta: Lumi'nin modlarını kurar/günceller, sonra klasörü tarar.
    /// Kurulum hatası toast'tır; klasörde ne varsa yine listelenir.
    public func load() async {
        if let toasts {
            await toasts.reporting { [service] in try await service.installBundled() }
        } else {
            try? await service.installBundled()
        }
        await reload()
    }

    /// Klasörü yeniden tarar (kullanıcı mod ekledi/sildi).
    public func reload() async {
        let value = await service.list()
        guard value != mods else { return }
        mods = value
        onModsChanged?(value)
    }
}

/// Mod klasörü olmayan bağlam (önizleme, testler).
public struct EmptyClaudeModService: ClaudeModServicing {
    public var directory: String { "" }
    public init() {}
    public func installBundled() async throws {}
    public func list() async -> [ClaudeMod] { [] }
}
