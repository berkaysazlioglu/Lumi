import Foundation
import LumiKit
import LumiState

/// Menü komutlarının store intent'lerine bağlanması (design/03 §2,
/// refactor 3.5/3.6).
///
/// Her komut `AppCommands.all`'daki kimliğiyle kaydedilir; menü item'ı
/// `MenuActionDispatcher` üzerinden buraya düşer. Yeni komut = tabloya bir
/// satır + buraya bir `register`.
@MainActor
enum AppMenuCommands {
    static func register(
        in dispatcher: MenuActionDispatcher,
        shared: SharedStores,
        openSettings: @escaping () -> Void
    ) {
        dispatcher.register(.newTerminal) {
            guard let active = shared.workspace.activeTab else { return }
            // Provider terminali = shell + launch komutu
            shared.terminals.spawn(
                in: active,
                command: shared.settings.current.aiProvider.launchCommand
            )
        }
        dispatcher.register(.closeTerminal) {
            guard let activeID = shared.terminals.activeTerminalID else { return }
            shared.terminals.close(activeID)
        }
        dispatcher.register(.openRepoSelector) {
            shared.workspace.isRepoSelectorOpen = true
        }
        dispatcher.register(.focusNextTerminal) {
            guard let active = shared.workspace.activeTab else { return }
            shared.terminals.focusNext(in: active)
        }
        dispatcher.register(.focusPreviousTerminal) {
            guard let active = shared.workspace.activeTab else { return }
            shared.terminals.focusPrevious(in: active)
        }
        dispatcher.register(.focusTerminalAtIndex) { index in
            guard let index, let active = shared.workspace.activeTab else { return }
            shared.terminals.focusIndex(index - 1, in: active)
        }
        dispatcher.register(.toggleMaximizeTerminal) {
            guard let active = shared.workspace.activeTab,
                  let id = shared.terminals.activeTerminalID else { return }
            shared.workspace.toggleMaximize(id, in: active)
        }
        dispatcher.register(.toggleLeftSidebar) { shared.workspace.toggleLeftSidebar() }
        dispatcher.register(.toggleRightSidebar) { shared.workspace.toggleRightSidebar() }
        dispatcher.register(.toggleFocusMode) { shared.workspace.toggleFocusMode() }
        dispatcher.register(.openSettings, openSettings)
    }
}
