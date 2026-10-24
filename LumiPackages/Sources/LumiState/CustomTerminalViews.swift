import Foundation
import LumiKit

/// Tek bir Custom View (karar 135): ad + üyelik/sıra.
public struct CustomTerminalView: Equatable, Sendable, Identifiable {
    public let id: CustomViewID
    public internal(set) var name: String
    /// Üyelik ve sıra tek kaynaktadır: view yalnız bu sırada yeri olan
    /// terminalleri gösterir (`TerminalArrangement.members`).
    var arrangement: TerminalArrangement
}

/// Custom View'ların tamamı (karar 135) — saf değer tipi.
///
/// **Boş view yoktur.** View yalnız bir terminalden doğar (`create(with:)`);
/// üyelik değiştiren her mutasyon sonunda hiç kaydı kalmayan view silinir ve
/// silinenlerin kimlikleri döner — çağıran (store) route'u ve yerleşimi
/// temizler. Açılışta henüz doğmamış resume kayıtları view'ı ayakta tutar;
/// doğmayacakları `finishRestore` düşürür.
public struct CustomTerminalViews: Equatable, Sendable {
    public private(set) var views: [CustomTerminalView] = []

    public init() {}

    /// Diskteki view'lar (`ui-state` → `customViews`). Sırası boş olan kayıt
    /// alınmaz — boş view yoktur.
    public init(restoring states: [CustomViewState]) {
        var seen = Set<String>()
        views = states.compactMap { state in
            guard seen.insert(state.id).inserted, !state.order.isEmpty else { return nil }
            return CustomTerminalView(
                id: CustomViewID(rawValue: state.id),
                name: state.name,
                arrangement: TerminalArrangement(restoring: state.order)
            )
        }
    }

    // MARK: - Sorgular

    public func view(_ id: CustomViewID) -> CustomTerminalView? {
        views.first { $0.id == id }
    }

    /// View'ın üyeleri sıralarıyla; view yoksa boş.
    public func members(of id: CustomViewID, among metas: [TerminalMeta]) -> [TerminalMeta] {
        view(id)?.arrangement.members(metas) ?? []
    }

    /// Terminalin üyesi olduğu view'lar (panelde göründükleri sırayla).
    public func views(containing terminal: TerminalMeta, among metas: [TerminalMeta]) -> [CustomTerminalView] {
        views.filter { view in view.arrangement.members(metas).contains { $0.id == terminal.id } }
    }

    /// Diske inen biçim: yalnız resume edilebilen üyeler yazılır; hiç
    /// resume edilebilen üyesi olmayan view yazılmaz (açılışta zaten boş
    /// kalıp silinirdi).
    public func persisted(_ metas: [TerminalMeta]) -> [CustomViewState] {
        views.compactMap { view in
            let order = view.arrangement.persistedKeys(view.arrangement.members(metas))
            guard !order.isEmpty else { return nil }
            return CustomViewState(id: view.id.rawValue, name: view.name, order: order)
        }
    }

    // MARK: - Mutasyonlar

    /// Terminalden yeni view doğar; ad rastgele üretilir (karar 135).
    @discardableResult
    public mutating func create(with terminal: TerminalID, name: String, id: CustomViewID = .make()) -> CustomViewID {
        var arrangement = TerminalArrangement()
        arrangement.insert(terminal)
        views.append(CustomTerminalView(id: id, name: name, arrangement: arrangement))
        return id
    }

    /// Dönüş: üyelik değişti mi (view yoksa ya da zaten üyeyse `false`).
    @discardableResult
    public mutating func add(_ terminal: TerminalID, to id: CustomViewID) -> Bool {
        guard let index = views.firstIndex(where: { $0.id == id }) else { return false }
        return views[index].arrangement.insert(terminal)
    }

    /// Dönüş: üyelik değişti mi ve boşalıp silinen view'lar.
    @discardableResult
    public mutating func remove(_ terminal: TerminalID, from id: CustomViewID) -> (changed: Bool, removed: [CustomViewID]) {
        guard let index = views.firstIndex(where: { $0.id == id }),
              views[index].arrangement.remove(terminal) else { return (false, []) }
        return (true, dropEmpty())
    }

    /// Dönüş: ad değişti mi. Geçersiz ad (`CustomViewName.sanitized`) reddedilir.
    @discardableResult
    public mutating func rename(_ id: CustomViewID, to raw: String) -> Bool {
        guard let name = CustomViewName.sanitized(raw),
              let index = views.firstIndex(where: { $0.id == id }),
              views[index].name != name else { return false }
        views[index].name = name
        return true
    }

    /// Canlı terminallerle kimlik eşlemesi: ölen üyeler düşer, resume edilen
    /// oturum `TerminalID`'ye sabitlenir. Dönüş: boşalıp silinen view'lar.
    @discardableResult
    public mutating func pin(_ metas: [TerminalMeta]) -> [CustomViewID] {
        for index in views.indices {
            views[index].arrangement.pinMembers(metas)
        }
        return dropEmpty()
    }

    /// Açılışta resume spawn'ları bittikten sonra: `aliveKeys`'te olmayan
    /// (hiç doğmayacak) bekleyen kayıtlar düşer. Dönüş: silinen view'lar.
    @discardableResult
    public mutating func finishRestore(aliveKeys: Set<String>, metas: [TerminalMeta]) -> [CustomViewID] {
        for index in views.indices {
            views[index].arrangement.pinMembers(metas)
            views[index].arrangement.dropResumed(notIn: aliveKeys)
        }
        return dropEmpty()
    }

    /// Karar 97 takası view içinde — yalnız iki üye arasında. Dönüş: sıra değişti mi.
    @discardableResult
    public mutating func swap(
        _ first: TerminalID,
        _ second: TerminalID,
        in id: CustomViewID,
        among metas: [TerminalMeta]
    ) -> Bool {
        guard let index = views.firstIndex(where: { $0.id == id }) else { return false }
        return views[index].arrangement.swap(first, second, among: metas, appendingUnplaced: false)
    }

    private mutating func dropEmpty() -> [CustomViewID] {
        let empty = views.filter(\.arrangement.isEmpty).map(\.id)
        guard !empty.isEmpty else { return [] }
        views.removeAll(where: \.arrangement.isEmpty)
        return empty
    }
}
