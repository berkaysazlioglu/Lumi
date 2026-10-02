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
        openSettings: @escaping () -> Void,
        openAbout: @escaping () -> Void,
        closeActiveProject: @escaping () -> Void
    ) {
        dispatcher.register(.newTerminal) {
            guard let active = shared.navigation.activeRepoPath else { return }
            // Provider terminali = shell + launch komutu
            shared.terminals.spawn(
                in: active,
                command: shared.settings.current.aiProvider.launchCommand
            )
        }
        // Electron paritesi: aktif terminal yoksa ⌘W repo TAB'ını kapatır
        // (karar 59). Tab kapanışı `requestCloseTab` guard'ından geçer —
        // minimize terminali olan tab dialog'suz kapanmaz.
        dispatcher.register(.closeTerminal) {
            if let activeID = shared.terminals.activeTerminalID {
                shared.terminals.close(activeID)
                return
            }
            guard let repoPath = shared.navigation.activeRepoPath,
                  let minimizedCount = shared.navigation.requestCloseTab(repoPath)
            else { return }
            shared.dialogs.present(.closeTab(CloseTabDialogState(
                repoPath: repoPath,
                repoName: (repoPath as NSString).lastPathComponent,
                minimizedCount: minimizedCount
            )))
        }
        // Karar 66: kaldırma `repos` + `workspaces`'i gerektirir; ikisi de
        // `SharedStores`'ta DEĞİL (kabuk repo feature'ına bağlanmaz — karar 33).
        // `openSettings` ile aynı desen: aksiyon dışarıdan enjekte edilir.
        dispatcher.register(.closeProject) { closeActiveProject() }
        dispatcher.register(.openRepoSelector) {
            shared.dialogs.isRepoSelectorOpen = true
        }
        // Karar 103: terminal gezinmesi aktif YÜZEYE vurur — repo route'unda
        // o checkout, All Terminals'ta o görünümün kart sırası.
        dispatcher.register(.focusNextTerminal) {
            guard let scope = shared.navigation.activeRoute.terminalScope else { return }
            shared.terminals.focusNext(in: scope)
        }
        dispatcher.register(.focusPreviousTerminal) {
            guard let scope = shared.navigation.activeRoute.terminalScope else { return }
            shared.terminals.focusPrevious(in: scope)
        }
        // Karar 65: indeks PROJELERE vurur. Eskiden `openTabs`'a vuruyordu —
        // kullanıcının hiçbir yerde GÖREMEDİĞİ bir listeye.
        dispatcher.register(.switchToProjectAtIndex) { index in
            guard let index else { return }
            shared.navigation.openProject(at: index - 1)
        }
        dispatcher.register(.focusTerminalAtIndex) { index in
            guard let index, let scope = shared.navigation.activeRoute.terminalScope else { return }
            shared.terminals.focusIndex(index - 1, in: scope)
        }
        dispatcher.register(.toggleMaximizeTerminal) {
            guard let scope = shared.navigation.activeRoute.terminalScope,
                  let id = shared.terminals.activeTerminalID else { return }
            shared.layout.toggleMaximize(id, in: scope)
        }
        dispatcher.register(.toggleLeftSidebar) { shared.layout.toggleSlot(.left) }
        dispatcher.register(.toggleRightSidebar) { shared.layout.toggleSlot(.right) }
        dispatcher.register(.toggleFocusMode) { shared.layout.toggleFocusMode() }
        dispatcher.register(.zoomIn) { shared.layout.zoomIn() }
        dispatcher.register(.zoomOut) { shared.layout.zoomOut() }
        dispatcher.register(.resetZoom) { shared.layout.resetZoom() }
        dispatcher.register(.openSettings, openSettings)
        dispatcher.register(.openAbout, openAbout)
    }
}
