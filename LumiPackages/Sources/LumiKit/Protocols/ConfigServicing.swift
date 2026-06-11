import Foundation

public enum ConfigEvent: Sendable, Equatable {
    /// Yan etki koordinatörü old/new'ü EŞİTLİKLE karşılaştırır — Electron'un
    /// truthiness bug'ı (0/boş string propagasyonu atlardı) yapısal olarak imkânsız.
    case configChanged(old: AppConfig, new: AppConfig)
}

/// Config + UI-state persistence sınırı (design/02 §2).
public protocol ConfigServicing: Actor {
    func config() async -> AppConfig
    func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) async throws
    func uiState() async -> UIState
    /// In-memory'ye anında uygulanır; disk yazımı 500ms debounce'lanır.
    func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) async
    func isFirstRun() async -> Bool
    /// Quit yolunda bekleyen debounce'lu yazımları hemen diske indirir.
    func flushPendingWrites() async
    func events() -> AsyncStream<ConfigEvent>
}
