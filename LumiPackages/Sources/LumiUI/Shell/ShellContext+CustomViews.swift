import LumiKit
import LumiState
import SwiftUI

/// Custom View intent'leri (karar 135) — store'a giden mutasyonların kullanıcıya
/// görünen yüzü (toast, gezinme) ve view'a terminal açarken hedef etiketi.
extension ShellContext {
    /// `Add to View ▸ New View`: isim sormaz, rastgele ad verir; kullanıcı
    /// yeni view'ın nerede durduğunu toast'tan öğrenir.
    public func addToNewCustomView(_ id: TerminalID) {
        guard let view = terminals.createCustomView(with: id),
              let name = terminals.customViews.view(view)?.name else { return }
        toasts.show(.success, title: "Created view \(name)", message: "Rename it from Views in the sidebar")
    }

    public func addToCustomView(_ id: TerminalID, _ view: CustomViewID) {
        terminals.addToCustomView(id, view)
    }

    /// Aktif route bu terminali içeren bir view ise o view — kart ve satır
    /// menülerindeki `Remove from View`'ın hedefi.
    public func activeCustomView(containing id: TerminalID) -> CustomViewID? {
        guard let view = activeTerminalScope?.customViewID,
              let meta = terminals.meta(for: id),
              terminals.contains(meta, in: .custom(view)) else { return nil }
        return view
    }

    /// View'a açılacak terminalin hedef checkout'u (çapa üyesi) — `New`
    /// butonunun yanındaki etiket.
    public func customViewSpawnLabel(_ view: CustomViewID) -> String? {
        terminals.spawnAnchor(in: view).map { checkoutLabel(for: $0.repoPath) }
    }

    /// View'daki checkout'lar (üye sırasıyla, tekil) ve her birinin view'daki
    /// son aktif üyesi — `New` dropdown'unda hedef seçimi: satır seçmek o
    /// üyeyi odaklar, çapa o checkout olur.
    public func customViewCheckouts(_ view: CustomViewID) -> [(path: String, member: TerminalID)] {
        var seen = Set<String>()
        let members = terminals.terminals(in: .custom(view))
        return members.compactMap { meta in
            guard seen.insert(meta.repoPath).inserted else { return nil }
            let candidates = members.filter { $0.repoPath == meta.repoPath && !terminals.isMinimized($0.id) }
            return (meta.repoPath, (candidates.first ?? meta).id)
        }
    }

    /// View route'unun başlığı; view silinmişse `nil`.
    public var activeCustomViewName: String? {
        activeTerminalScope?.customViewID.flatMap { terminals.customViews.view($0)?.name }
    }
}
