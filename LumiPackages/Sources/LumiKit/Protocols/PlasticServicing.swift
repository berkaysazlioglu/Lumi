import Foundation

/// Plastic SCM okuma sınırı (karar 45). Git'in `GitReading`i gibi
/// **sessiz-boş sözleşme**: hata → nil / boş koleksiyon + log. Plastic
/// çalışma alanı olmayan dizinler ve `cm` kurulu olmayan makineler rutin
/// durumdur; UI'ya hata sızmaz, panel boş kalır.
///
/// Yalnız okuma: checkin/undo/update kapsam dışıdır (karar 45 — "git gibi
/// gelişmiş olması gerekmez"). Tüm çağrılar `cm` CLI'sından geçer ve
/// binary `BinaryLocating` ile çözülür; sabit path yoktur.
public protocol PlasticReading: Sendable {
    /// `cm` PATH'te (veya bilinen kurulum dizinlerinde) var mı? Görünümün
    /// "CLI bulunamadı" kapısı; süreç ömrü boyunca bir kez ölçülmesi yeterlidir.
    func isCLIAvailable() async -> Bool
    /// Çalışma alanı başlığı: changeset + repo@server + branch. Dizin bir
    /// Plastic çalışma alanı değilse nil.
    func workspaceInfo(workspacePath: String) async -> PlasticWorkspaceInfo?
    /// Changed/added/deleted/moved/private öğeler (ignored hariç); path'ler
    /// çalışma alanı köküne göre relative'dir.
    func status(workspacePath: String) async -> [PlasticFileChange]
    /// Repo-geneli en yeni `limit` changeset, yeniden eskiye. Tarih filtresi
    /// yoktur: `cm find`in tarih literali locale'e bağlıdır; pencereyi store
    /// uygular.
    func recentChangesets(workspacePath: String, limit: Int) async -> [PlasticChangeset]
}
