import Foundation
import LumiKit
import Observation

/// File-tree arama kutusunun durum makinesi (refactor 6.7).
///
/// Eskiden `FileTreeSidebar` içinde dört `@State` + elle yönetilen bir `Task`
/// olarak yaşıyordu; view hem debounce'ı hem iptali hem de sonuç sırasını
/// biliyordu. Buraya taşındı: view artık yalnız `query`/`results`/`isSearching`
/// okur ve `setQuery(_:tree:)` / `cancel()` çağırır.
///
/// **Sonuç tipi enjekte edilir** (`Rows`): satır düzleştirme LumiUI'nın işi
/// (`FileTreeRows`), state katmanı UI tiplerini tanımaz. `search` closure'ı
/// `@Sendable` ve nonisolated olduğundan hesap MainActor DIŞINDA koşar — büyük
/// repoda her tuş vuruşunda ana thread'de recursive tarama yapılmaz.
///
/// Sıra garantisi: her `setQuery` önceki task'ı iptal eder, task hem uykudan
/// hem hesaptan sonra iptali kontrol eder; bayat sonuç asla yazılmaz.
@Observable
@MainActor
public final class FileTreeSearchModel<Rows: Sendable> {
    /// Kullanıcının yazdığı ham sorgu (anında güncellenir — TextField takılmaz).
    public private(set) var query: String = ""
    /// Son tamamlanan aramanın sonucu; `nil` = arama yok ya da ilk sonuç
    /// henüz gelmedi (view bu sırada normal ağacı gösterir — stale-while-filter).
    public private(set) var results: Rows?

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let search: @Sendable ([FileTreeNode], String) -> Rows
    @ObservationIgnored private var filterTask: Task<Void, Never>?

    /// - Parameters:
    ///   - debounce: Son tuş vuruşundan sonra beklenen süre.
    ///   - search: Saf filtre (ağaç + trim'lenmiş sorgu → satırlar). MainActor
    ///     dışında çağrılır.
    /// `nonisolated`: view'ların `@State` başlangıç değeri olarak kurulabilsin
    /// (stored-property initializer'ı MainActor bağlamında koşmaz).
    public nonisolated init(
        debounce: Duration,
        search: @escaping @Sendable ([FileTreeNode], String) -> Rows
    ) {
        self.debounce = debounce
        self.search = search
    }

    /// Sorgu boşluk-dışı bir şey içeriyor mu — view'ın "arama modundayım"
    /// kapısı (klasör toggle'ı kapalı, boş-durum metni değişir).
    public var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Yeni sorgu (ya da ağaç tazelendiğinde aynı sorgu). Boş sorgu aramayı
    /// kapatır: uçuştaki task iptal edilir, sonuç temizlenir, hiç arama koşmaz.
    public func setQuery(_ query: String, tree: [FileTreeNode]) {
        self.query = query
        filterTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            filterTask = nil
            results = nil
            return
        }
        filterTask = Task { [debounce, search] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let computed = await Self.compute(search, tree: tree, query: trimmed)
            guard !Task.isCancelled else { return }
            self.results = computed
        }
    }

    /// Arama kutusu kapandı / repo değişti: her şey sıfırlanır.
    public func cancel() {
        filterTask?.cancel()
        filterTask = nil
        query = ""
        results = nil
    }

    /// Hesabı MainActor dışına taşıyan nonisolated köprü.
    private nonisolated static func compute(
        _ search: @Sendable ([FileTreeNode], String) -> Rows,
        tree: [FileTreeNode],
        query: String
    ) async -> Rows {
        search(tree, query)
    }
}
