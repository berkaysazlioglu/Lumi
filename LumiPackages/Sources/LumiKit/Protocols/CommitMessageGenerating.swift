import Foundation

/// Commit/checkin mesajı üretim isteği (karar 46): VCS'den bağımsız — Git
/// seçili dosyaların çalışma ağacı diff'ini, Plastic yalnız dosya listesini
/// verir (Plastic'te çalışma alanı diff'i CLI'dan metin olarak alınamaz).
public struct CommitMessageRequest: Sendable, Equatable {
    public struct Change: Sendable, Equatable {
        public let path: String
        public let status: FileChangeStatus

        public init(path: String, status: FileChangeStatus) {
            self.path = path
            self.status = status
        }
    }

    /// Kullanıcıya görünen VCS adı ("Git" / "Plastic SCM") — prompt'ta geçer.
    public let vcsName: String
    public let changes: [Change]
    /// Unified diff metni; yoksa boş.
    public let diff: String

    public init(vcsName: String, changes: [Change], diff: String = "") {
        self.vcsName = vcsName
        self.changes = changes
        self.diff = diff
    }
}

/// Commit mesajı üreticisi sınırı (karar 46). **Fırlatan sözleşme:** kullanıcı
/// düğmeye bastı; CLI yok / oturum yok / boş yanıt görünür hatadır
/// (`LumiError.cliNotFound` ya da `.commitMessageGenerationFailed`).
///
/// Üretim `claude -p` ile arka planda, düşük effort'ta, araçsız tek turn'dür;
/// Lumi'nin terminal oturumlarına dokunmaz.
public protocol CommitMessageGenerating: Sendable {
    func generate(_ request: CommitMessageRequest) async throws -> String
}
