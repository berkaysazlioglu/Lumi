import Foundation
import LumiKit

/// Navigasyonun terminal yüzeyinden ihtiyaç duyduğu DAR yüzey (refactor 5.2).
///
/// **Neden protokol, neden event değil?** İki gereksinim event'le karşılanamaz:
/// (1) `minimizedTerminals` bir SORGUdur — close-tab guard'ı cevabı senkron
/// ister, tek yönlü bir event akışı bunu veremez; (2) `activateRepo` ile
/// `persist()` arasındaki SIRA davranışın parçasıdır (yüzey öne alınmadan
/// snapshot yazılmamalı) — sırayı `AppComposition`'daki bir köprüye taşımak
/// garantiyi kompozisyona kaçırırdı. Protokol LumiState içinde kaldığı için
/// modül grafiği de bozulmaz ve testte sahte ile karşılanır.
///
/// Modül DIŞI tüketiciler (git/repo cache eviction) tam tersi durumdadır —
/// sorgu yok, sıra yok — onlar `NavigationStore.onTabClosed` event'iyle bağlanır.
@MainActor
public protocol TerminalFocusCoordinating: AnyObject {
    /// Tab/route geçişi: yüzeyi bu repo'ya alır ve son aktif terminali odaklar.
    func activateRepo(_ repoPath: String)
    /// Odağı doğrudan set eder (`nil` = odak yok).
    func focus(_ id: TerminalID?)
    /// Repo'nun tüm terminallerini kapatır (tab kapanışı).
    func closeAll(in repoPath: String)
    /// Close-tab guard'ının saydığı minimize terminaller.
    func minimizedTerminals(in repoPath: String) -> [TerminalMeta]
    /// Maximize hedefinin hâlâ görünür olup olmadığı.
    func visibleTerminals(in repoPath: String) -> [TerminalMeta]
}

extension TerminalListStore: TerminalFocusCoordinating {}
