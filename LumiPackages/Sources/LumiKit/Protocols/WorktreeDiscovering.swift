import Foundation

/// Git worktree keşfi ve izlenmesi (karar 115, Orca paritesi).
///
/// Liste her seferinde git'ten okunur; izleyici yalnız "yeniden oku"
/// sinyali verir. Bloklayıcı bekleme yoktur (karar 86): süreçler
/// `ProcessRunning` üzerinden, izleyiciler kendi `DispatchQueue`'larında koşar.
public protocol WorktreeDiscovering: Actor {
    /// `git worktree list --porcelain`. **Fırlatır** — git hatası
    /// "liste boş" demek değildir; tüketici o projede hiçbir satırı
    /// düşürmemelidir (Orca'daki boş-liste-otoriter hatası taşınmaz).
    func worktrees(projectPath: String) async throws -> [GitWorktreeEntry]

    /// İzlenecek küme: projelerin ortak git dizinindeki `worktrees/` (yoksa
    /// ortak git dizininin kendisi — ilk `git worktree add` onu oluşturur) ve
    /// checkout'ların üst dizinleri (klasör elle silinince). Önceki küme
    /// tamamen bununla değiştirilir.
    func watch(projectPaths: [String], checkoutPaths: [String]) async

    /// Debounce'lu değişim sinyali. `nonisolated`: tüketici Task'ı kurulmadan
    /// önce senkron alınabilmeli (bkz. `RepoServicing.events`).
    nonisolated func changes() -> AsyncStream<Void>
}
