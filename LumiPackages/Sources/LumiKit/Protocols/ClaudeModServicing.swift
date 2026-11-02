import Foundation

/// Mod klasörünü (`~/.lumi/mods`) yöneten servis yüzü (karar 142).
public protocol ClaudeModServicing: Sendable {
    /// Mod klasörünün mutlak yolu.
    var directory: String { get }
    /// Lumi'nin kendi modlarını klasöre yazar: yoksa kurar, sürümü farklıysa
    /// üzerine yazar (kullanıcının bu klasörde yaptığı değişiklik güncellemede
    /// gider). Kullanıcının kendi modlarına dokunmaz.
    func installBundled() async throws
    /// `.claude-plugin/plugin.json` taşıyan alt klasörler, ada göre sıralı.
    /// Klasör yoksa boş döner (hata değil).
    func list() async -> [ClaudeMod]
}
