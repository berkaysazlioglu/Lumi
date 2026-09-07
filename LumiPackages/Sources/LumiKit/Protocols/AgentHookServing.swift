import Foundation

/// Hook olaylarını kabul eden loopback sunucu sınırı (karar 45).
///
/// Claude Code / Codex, kurulu hook script'i üzerinden her yaşam döngüsü
/// olayında (`UserPromptSubmit`, `Stop`, `PermissionRequest`…) buraya POST
/// eder; sunucu doğrular, `AgentHookEvent`'e çevirir ve akışa yayar. Terminal
/// başlığı ya da çıktı sessizliği tahminine gerek kalmaz.
public protocol AgentHookServing: Sendable {
    /// Dinlemeye başlar; port işletim sisteminden alınır. İkinci çağrı mevcut
    /// uç noktayı döndürür.
    func start() async throws -> AgentHookEndpoint
    func stop() async
    func events() -> AsyncStream<AgentHookEvent>
}

/// Sağlayıcı ayar dosyalarına (`~/.claude/settings.json`, `~/.codex/hooks.json`
/// + `config.toml` güven kayıtları) Lumi'nin yönetilen hook girdilerini yazan
/// sınır. Idempotent: her açılışta çağrılır, değişiklik yoksa dosyaya dokunmaz.
public protocol AgentHookInstalling: Sendable {
    func install() async -> [AgentHookInstallResult]
    /// Yönetilen girdileri kaldırır; kullanıcının kendi hook'ları korunur.
    func uninstall() async -> [AgentHookInstallResult]
}
