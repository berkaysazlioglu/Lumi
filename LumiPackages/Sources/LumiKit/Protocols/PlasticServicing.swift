import Foundation

/// Plastic SCM okuma sınırı (karar 46). Git'in `GitReading`i gibi
/// **sessiz-boş sözleşme**: hata → nil / boş koleksiyon + log. Plastic
/// çalışma alanı olmayan dizinler ve `cm` kurulu olmayan makineler rutin
/// durumdur; UI'ya hata sızmaz, panel boş kalır.
///
/// Update/switch/merge kapsam dışıdır (karar 46 — "git gibi gelişmiş
/// olması gerekmez"). Tüm çağrılar `cm` CLI'sından geçer ve binary
/// `BinaryLocating` ile çözülür; sabit path yoktur.
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
    /// Karar 47: seçili öğelerin unified diff metni (commit mesajı üretimine
    /// girdi). Değişen dosya için taban `cm cat "rev:<path>#cs:<changesetID>"`
    /// ile alınıp yerel dosyayla `diff -u` yapılır; eklenen/private dosya
    /// `/dev/null`a karşı tamamı-ekleme, silinen dosya tek satır notla gelir.
    /// Sessiz: hata → o dosya atlanır.
    func workingTreeDiffText(workspacePath: String, changesetID: Int, changes: [PlasticFileChange]) async -> String
}

/// **Yazma sözleşmesi** (karar 46 eki): çalışma alanını değiştiren iki
/// operasyon; başarısızlık her zaman görünür hatadır (`LumiError.plasticFailed`).
/// Dosya path'leri çalışma alanı köküne göre relative'dir ve kök-içi
/// doğrulamasından geçer (karar 11).
public protocol PlasticWriting: Sendable {
    /// `cm checkin <paths> -c=<message>`: seçili öğeler tek changeset olur.
    /// Private (PR) öğeler de dahildir (`--private`), ayrı `cm add` gerekmez.
    func checkin(workspacePath: String, message: String, files: [String]) async throws
    /// `cm undo <paths>`: öğenin yerel değişikliğini GERİ ALINAMAZ biçimde
    /// atar (Plastic'in kendi uyarısı). Private öğede etkisizdir; UI o durumda
    /// undo yerine çöpe taşımayı sunar.
    func undo(workspacePath: String, files: [String]) async throws
}

/// Tam Plastic yüzeyi — composition root ve `PlasticService` bunu kullanır.
public typealias PlasticServicing = PlasticReading & PlasticWriting
