import Foundation

/// Git operasyonları sınırı (design/02 §4), hata sözleşmesine göre üçe ayrılmış
/// (refactor 3.8 — ISP): tüketiciler yalnız kullandıkları yüzeye bağlanır ve
/// fake'ler küçülür.
///
/// TÜM "repo + relative path" alan metodlar kök-içi doğrulaması yapar
/// (karar 11 — Electron'daki tutarsızlık taşınmaz).

/// **Sessiz-boş sözleşme:** hata durumunda BOŞ koleksiyon / boş önizleme döner
/// (git olmayan dizinler rutin olarak açılır) ama loglar. UI'ya hata sızmaz —
/// panel boş kalır (Electron paritesi).
public protocol GitReading: Sendable {
    func branches(repoPath: String) async -> [GitBranch]
    /// `branch` verilmiş, default branch (main→master) mevcut ve farklıysa
    /// aralık `defaultBranch..branch`tır — yalnız branch'e özgü commit'ler
    /// (en kolay gözden kaçan davranış). Her zaman max 50.
    func commits(repoPath: String, branch: String?) async -> [GitCommit]
    func status(repoPath: String) async -> [GitFileChange]
    /// Karar 6 (lazy): commit seçilince yalnız dosya listesi.
    func commitFiles(repoPath: String, sha: String) async -> [CommitFile]
    /// Karar 21: görsel dosyalar diff yerine önizlemeyle gösterilir. `sha`
    /// verilirse commit'in öncesi/sonrası blob'ları (`sha^:file` / `sha:file`),
    /// verilmezse `HEAD:file` ↔ disk. Liste operasyonları gibi SESSİZ: eksik
    /// taraf nil'dir (eklenen/silinen dosya ya da root commit rutin durumdur).
    func imagePreview(repoPath: String, file: String, sha: String?) async -> ImagePreview
}

/// **Fırlatan sözleşme:** kullanıcı bir dosyayı açtı/diff istedi; başarısızlık
/// görünür hatadır (`LumiError`, karar 5) — sessizce boş içerik gösterilmez.
public protocol GitContentReading: Sendable {
    func readFile(repoPath: String, file: String) async throws -> String
    /// Working-tree diff'i: HEAD ↔ disk; untracked dosyada tamamı ekleme.
    func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff
    /// Karar 6 (lazy): dosyaya tıklanınca tek dosyanın diff'i.
    func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff
}

/// **Yazma sözleşmesi:** repoyu değiştiren tek operasyon; başarısızlık her
/// zaman görünür hatadır.
public protocol GitWriting: Sendable {
    func commit(repoPath: String, message: String, files: [String]) async throws
}

/// Tam git yüzeyi — composition root ve `GitService` bu bileşimi kullanır.
/// Tüketiciler (store'lar) dar protokollere bağlanır.
public typealias GitServicing = GitReading & GitContentReading & GitWriting
