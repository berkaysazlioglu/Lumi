import Foundation
import LumiKit

/// All Terminals görünümünün KENDİ kart sırası (karar 103).
///
/// **Neden ayrı bir sıra?** Repo görünümlerinin sırası tam terminal
/// listesindedir (karar 97). All Terminals'ta farklı projelerin kartlarını o
/// listede takas etmek, projelerin kendi görünümündeki sırayı da bozardı. Bu
/// tip o listeye dokunmaz: yalnız All Terminals'ın sırasını tutar ve proje
/// görünümleri bundan hiç etkilenmez.
///
/// **Kimlik iki türlüdür.** Çalışırken bir terminal `TerminalID` ile tanınır;
/// bu kimlik süreçle ölür. Açılışta sıra, resume listesiyle (karar 90) geri
/// gelen Claude/Codex oturumlarının kimliğinden kurulur (`.resumed`). Resume
/// edilen terminal doğduğunda (`pin`) bu kayıt `TerminalID`'ye çevrilir —
/// sonraki bir `/clear` (karar 94) oturum kimliğini değiştirse de terminal
/// yerini korur. Resume edilemeyen terminaller (düz shell) zaten açılışta
/// geri gelmez; çalışırken yine `TerminalID` ile sıralanır.
///
/// **Saf değer tipi:** `ordered` render sırasında çağrılabilir (mutasyon yok);
/// mutasyonlar (`pin`, `swap`) olay anında store'dan gelir.
public struct TerminalArrangement: Equatable, Sendable {
    enum Entry: Hashable, Sendable {
        case terminal(TerminalID)
        /// Henüz doğmamış (ya da hiç doğmayacak) resume edilen oturum.
        case resumed(String)
    }

    private(set) var entries: [Entry]

    /// `keys`: diskteki sıra — `persistedKeys` çıktısı.
    public init(restoring keys: [String] = []) {
        var seen = Set<String>()
        entries = keys.filter { seen.insert($0).inserted }.map(Entry.resumed)
    }

    // MARK: - Sorgular

    /// `metas`'ı bu sıraya dizer. Sırada yeri olmayanlar (yeni spawn'lar)
    /// sona, gelen listedeki kendi sıralarıyla eklenir.
    public func ordered(_ metas: [TerminalMeta]) -> [TerminalMeta] {
        let placed = placements(of: metas)
        return metas.enumerated()
            .sorted { lhs, rhs in
                switch (placed[lhs.element.id], placed[rhs.element.id]) {
                case let (left?, right?): left < right
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// Diske inen sıra: resume edilebilen terminallerin oturum kimlikleri.
    /// Yalnız canlılar yazılır — doğmamış resume kayıtları bir sonraki
    /// açılışa sarkmaz (resume listesiyle aynı kural, karar 90).
    public func persistedKeys(_ metas: [TerminalMeta]) -> [String] {
        ordered(metas).compactMap(\.resumeKey)
    }

    // MARK: - Mutasyonlar

    /// Canlı terminalleri kimlikleriyle sabitler: eşleşen resume kayıtları
    /// `TerminalID`'ye döner, ölü terminaller düşer, yeri olmayanlar sona
    /// eklenir. Henüz doğmamış resume kayıtları yerinde bekler — sonradan
    /// doğan oturum kendi eski yerine oturur.
    public mutating func pin(_ metas: [TerminalMeta]) {
        let placed = placements(of: metas)
        let idAtEntry = Dictionary(uniqueKeysWithValues: placed.map { ($1, $0) })
        var next: [Entry] = []
        for (index, entry) in entries.enumerated() {
            if let id = idAtEntry[index] {
                next.append(.terminal(id))
            } else if case .resumed = entry {
                next.append(entry)
            }
        }
        next += metas.filter { placed[$0.id] == nil }.map { .terminal($0.id) }
        guard next != entries else { return }
        entries = next
    }

    /// Karar 97 takası All Terminals'ta: iki kart birbirinin yerine geçer,
    /// aradaki (minimize edilmiş dahil) hiçbir kart kıpırdamaz. Repo sınırı
    /// yoktur. Dönüş: sıra değişti mi.
    @discardableResult
    public mutating func swap(_ first: TerminalID, _ second: TerminalID, among metas: [TerminalMeta]) -> Bool {
        pin(metas)
        guard first != second,
              let firstIndex = entries.firstIndex(of: .terminal(first)),
              let secondIndex = entries.firstIndex(of: .terminal(second)) else { return false }
        entries.swapAt(firstIndex, secondIndex)
        return true
    }

    // MARK: - Eşleme

    /// Terminal → sıradaki kaydın indeksi. Her kayıt en çok bir terminale,
    /// her terminal en çok bir kayda eşlenir; aynı oturum kimliğini taşıyan
    /// ikinci terminal yeni sayılır.
    private func placements(of metas: [TerminalMeta]) -> [TerminalID: Int] {
        var placed: [TerminalID: Int] = [:]
        let byID = Dictionary(metas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Önce kimlikle sabitlenenler: bir resume kaydı, kendi yeri zaten
        // sabit olan terminali çalamasın.
        for (index, entry) in entries.enumerated() {
            guard case .terminal(let id) = entry, byID[id] != nil, placed[id] == nil else { continue }
            placed[id] = index
        }
        for (index, entry) in entries.enumerated() {
            guard case .resumed(let key) = entry,
                  let match = metas.first(where: { $0.resumeKey == key && placed[$0.id] == nil })
            else { continue }
            placed[match.id] = index
        }
        return placed
    }
}

extension TerminalMeta {
    /// Açılışta bu terminali geri getirecek oturum kimliği — resume listesinin
    /// (karar 23/80) seçtiği alanın aynısı. Düz shell'de `nil`.
    var resumeKey: String? {
        provider == .codex ? codexSessionID : claudeSessionID
    }
}
