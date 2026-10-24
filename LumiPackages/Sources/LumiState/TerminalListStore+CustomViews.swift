import Foundation
import LumiKit

/// Custom View intent'leri (karar 135). Saf kurallar `CustomTerminalViews`'tadır;
/// burada yalnız store'un canlı listesiyle eşleme, kalıcılık sinyali
/// (`onOrderChanged` → karar 90 checkpoint'i) ve silinen view bildirimi yaşar.
extension TerminalListStore {
    /// Terminalin üyesi olduğu view'lar — `Add to View` menüsü işaretler,
    /// `Remove from View` buradan doğar.
    public func customViews(containing id: TerminalID) -> [CustomTerminalView] {
        guard let meta = meta(for: id) else { return [] }
        return customViews.views(containing: meta, among: terminals)
    }

    /// Terminalden yeni view doğar (boş view yoktur); ad rastgeledir.
    @discardableResult
    public func createCustomView(with id: TerminalID) -> CustomViewID? {
        guard meta(for: id) != nil else { return nil }
        let name = CustomViewName.random(excluding: Set(customViews.views.map(\.name)))
        let view = customViews.create(with: id, name: name)
        lastActiveByView[view] = id
        onOrderChanged?()
        return view
    }

    public func addToCustomView(_ id: TerminalID, _ view: CustomViewID) {
        guard meta(for: id) != nil, customViews.add(id, to: view) else { return }
        onOrderChanged?()
    }

    /// Terminali kapatmaz; view'ın son üyesiyse view silinir.
    public func removeFromCustomView(_ id: TerminalID, _ view: CustomViewID) {
        let result = customViews.remove(id, from: view)
        guard result.changed else { return }
        if lastActiveByView[view] == id { lastActiveByView[view] = nil }
        if !result.removed.isEmpty { customViewsRemoved(result.removed) }
        onOrderChanged?()
    }

    /// View'ı siler; üyeleri kapatmaz (karar 135).
    public func deleteCustomView(_ view: CustomViewID) {
        guard customViews.delete(view) else { return }
        customViewsRemoved([view])
        onOrderChanged?()
    }

    public func renameCustomView(_ view: CustomViewID, to name: String) {
        guard customViews.rename(view, to: name) else { return }
        onOrderChanged?()
    }

    /// View'a terminal açarken hedef checkout'u veren üye: aktif terminal
    /// üyeyse o, değilse view'ın son aktif üyesi, o da yoksa ilk üye.
    public func spawnAnchor(in view: CustomViewID) -> TerminalMeta? {
        let members = customViews.members(of: view, among: terminals)
        let preferred = [activeTerminalID, lastActiveByView[view]].compactMap { $0 }
        for id in preferred {
            if let member = members.first(where: { $0.id == id }) { return member }
        }
        return members.first
    }

    /// Karar 136: kapsamdaki aktif terminalin checkout'u (sağ panelin hedefi).
    public func activeTerminalRepoPath(in scope: TerminalScope) -> String? {
        guard let id = activeTerminalID, let meta = meta(for: id), contains(meta, in: scope) else { return nil }
        return meta.repoPath
    }

    // MARK: - Açılış (karar 135 — karar 103 `restoreAllArrangement` kalıbı)

    /// Diskteki view'lar resume spawn'larından ÖNCE kurulur ki doğan oturumlar
    /// eski view'larına ve yerlerine otursun.
    public func restoreCustomViews(_ states: [CustomViewState]) {
        var restored = CustomTerminalViews(restoring: states)
        let removed = restored.pin(terminals)
        customViews = restored
        if !removed.isEmpty { customViewsRemoved(removed) }
    }

    /// Resume spawn'ları bittikten sonra: hiç doğmayacak oturumların kayıtları
    /// düşer, üyesiz kalan view silinir. "Doğdu mu" servisin canlı kümesinden
    /// okunur — store `.spawned`'ı henüz uygulamamış olabilir.
    public func finishCustomViewRestore(aliveTerminals: [TerminalMeta]) {
        let aliveKeys = Set(aliveTerminals.compactMap(\.resumeKey))
        let removed = customViews.finishRestore(aliveKeys: aliveKeys, metas: terminals)
        if !removed.isEmpty { customViewsRemoved(removed) }
    }

    // MARK: - Olay eşlemesi

    func pinCustomViews() {
        let removed = customViews.pin(terminals)
        if !removed.isEmpty { customViewsRemoved(removed) }
    }

    func joinPendingView(_ id: TerminalID) {
        guard let view = pendingViewJoins.removeValue(forKey: id),
              customViews.add(id, to: view) else { return }
        onOrderChanged?()
    }

    func rememberActiveMember(_ meta: TerminalMeta) {
        for view in customViews.views(containing: meta, among: terminals) {
            lastActiveByView[view.id] = meta.id
        }
    }

    private func customViewsRemoved(_ ids: [CustomViewID]) {
        for id in ids { lastActiveByView[id] = nil }
        pendingViewJoins = pendingViewJoins.filter { !ids.contains($0.value) }
        onCustomViewsRemoved?(ids)
    }
}
