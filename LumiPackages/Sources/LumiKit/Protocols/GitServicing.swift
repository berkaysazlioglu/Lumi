import Foundation

/// Git operasyonları sınırı (design/02 §4, spec/12).
///
/// Hata stratejisi paritesi (spec/12): read-only liste operasyonları
/// (commits/branches/status) hata durumunda BOŞ koleksiyon döner (git
/// olmayan dizinler rutin olarak açılır) ama loglar; içerik operasyonları
/// (readFile/diff'ler) ve commit `LumiError` fırlatır (karar 5).
/// TÜM "repo + relative path" alan metodlar kök-içi doğrulaması yapar
/// (karar 11 — Electron'daki tutarsızlık taşınmaz).
public protocol GitServicing: Sendable {
    func branches(repoPath: String) async -> [GitBranch]
    /// `branch` verilmiş, default branch (main→master) mevcut ve farklıysa
    /// aralık `defaultBranch..branch`tır — yalnız branch'e özgü commit'ler
    /// (spec/12 §2, en kolay gözden kaçan davranış). Her zaman max 50.
    func commits(repoPath: String, branch: String?) async -> [GitCommit]
    func status(repoPath: String) async -> [GitFileChange]
    func commit(repoPath: String, message: String, files: [String]) async throws
    func readFile(repoPath: String, file: String) async throws -> String
    /// Working-tree diff'i: HEAD ↔ disk; untracked dosyada tamamı ekleme.
    func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff
    /// Karar 6 (lazy): commit seçilince yalnız dosya listesi.
    func commitFiles(repoPath: String, sha: String) async -> [CommitFile]
    /// Karar 6 (lazy): dosyaya tıklanınca tek dosyanın diff'i.
    func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff
    /// Karar 21: görsel dosyalar diff yerine önizlemeyle gösterilir. `sha`
    /// verilirse commit'in öncesi/sonrası blob'ları (`sha^:file` / `sha:file`),
    /// verilmezse `HEAD:file` ↔ disk. Liste operasyonları gibi SESSİZ: eksik
    /// taraf nil'dir (eklenen/silinen dosya ya da root commit rutin durumdur).
    func imagePreview(repoPath: String, file: String, sha: String?) async -> ImagePreview
}
