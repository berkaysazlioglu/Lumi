import LumiKit
import LumiState
import SwiftUI

/// `Add to View` / `Remove from View` (karar 135) — kart başlığının ve Projects
/// ajan satırının sağ tık menüsüne aynı içerik iner. Lumi `PopoverMenu`
/// öğeleridir: native `.contextMenu` sistem görünümüyle açılıyordu ve terminal
/// çıktısıyla satır her yeniden çizildiğinde `NSMenu` baştan kurulduğu için
/// `Add to View` alt menüsü hover'da aç-kapa titriyordu.
enum CustomViewMenuItems {
    @MainActor
    static func items(
        for terminalID: TerminalID,
        shell: ShellContext,
        dismiss: @escaping () -> Void
    ) -> [PopoverMenu.Item] {
        let memberOf = Set(shell.terminals.customViews(containing: terminalID).map(\.id))
        let views = shell.terminals.customViews.views
        // Üye olunan view işaretli ve pasif — tekrar eklemek anlamsız. Toggle
        // satırı kendiliğinden kapatmadığı için eylem menüyü kendisi kapatır.
        var submenu: [PopoverMenu.Item] = views.map { view in
            let isMember = memberOf.contains(view.id)
            return .toggle(view.name, isOn: isMember, isEnabled: !isMember) {
                dismiss()
                shell.addToCustomView(terminalID, view.id)
            }
        }
        if !views.isEmpty {
            submenu.append(.divider)
        }
        submenu.append(.action("New View", icon: "plus") { shell.addToNewCustomView(terminalID) })

        var items: [PopoverMenu.Item] = [
            .submenu("Add to View", icon: CustomViewRoute.icon, items: submenu),
        ]
        if let view = shell.activeCustomView(containing: terminalID) {
            items.append(.action("Remove from View", icon: "minus.circle") {
                shell.terminals.removeFromCustomView(terminalID, view)
            })
        }
        return items
    }
}
