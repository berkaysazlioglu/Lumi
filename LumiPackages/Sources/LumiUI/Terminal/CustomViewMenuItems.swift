import LumiKit
import LumiState
import SwiftUI

/// `Add to View` / `Remove from View` (karar 135) — kart başlığının ve Projects
/// ajan satırının sağ tık menüsüne aynı içerik iner. Native `.contextMenu`
/// içeriğidir: alt menü sistemin kendi `Menu`'südür.
struct CustomViewMenuItems: View {
    let terminalID: TerminalID
    @Shell private var shell

    var body: some View {
        let memberOf = Set(shell.terminals.customViews(containing: terminalID).map(\.id))
        Menu("Add to View") {
            ForEach(shell.terminals.customViews.views) { view in
                if memberOf.contains(view.id) {
                    // Zaten üye: işaretli ve pasif — tekrar eklemek anlamsız.
                    Button { } label: { Label(view.name, systemImage: "checkmark") }
                        .disabled(true)
                } else {
                    Button(view.name) { shell.addToCustomView(terminalID, view.id) }
                }
            }
            if !shell.terminals.customViews.views.isEmpty {
                Divider()
            }
            Button("New View") { shell.addToNewCustomView(terminalID) }
        }
        if let view = shell.activeCustomView(containing: terminalID) {
            Button("Remove from View") { shell.terminals.removeFromCustomView(terminalID, view) }
        }
    }
}
