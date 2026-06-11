import Foundation

/// Persona sınırı (design/02 §5, spec/13 §2).
/// Seed: default'lar HER startup'ta ezilir (asimetrinin persona tarafı).
public protocol PersonaServicing: Actor {
    /// Project persona'lar aynı id'li user persona'yı GİZLER (spec/13 §2.4).
    /// projectPath verilirse o dizin yüklenir ve izlenmeye başlanır.
    func personas(projectPath: String?) async -> [Persona]
    func seedDefaults() async
    /// Yeni terminal + task=label + provider'a göre base komut + flag enjeksiyonu.
    func spawn(personaID: String, repoPath: String) async throws -> TerminalMeta
    func events() -> AsyncStream<Void>
}

/// Action sınırı (design/02 §6, spec/13 §3).
/// Seed: hedefte `modified_at` varsa korunur (asimetrinin action tarafı);
/// default silinirse watcher reseed'le anında geri getirir.
public protocol ActionServicing: Actor {
    func actions(projectPath: String?) async -> [Action]
    func seedDefaults() async
    /// Daima YENİ terminal; limit aşımı görünür hatadır (karar 5/11).
    func execute(actionID: String, repoPath: String) async throws -> TerminalMeta
    /// Dosya adına değil içerikteki `id` alanına göre arar (spec/13 §3.5).
    func delete(actionID: String, scope: PresetScope, projectPath: String?) async throws
    /// Yeniden eskiye sıralı backup timestamp'leri.
    func history(actionID: String) async -> [ActionVersion]
    func restore(actionID: String, version: String) async throws
    /// AI destekli oluşturma/düzenleme (spec/13 §3.8-3.9).
    func createNew(repoPath: String?) async throws -> TerminalMeta
    func edit(actionID: String, projectPath: String?) async throws -> TerminalMeta
    func events() -> AsyncStream<Void>
}
