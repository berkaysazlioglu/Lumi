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
        checkForUpdates: @escaping () -> Void,
        closeActiveProject: @escaping () -> Void,
        toggleOrchestrator: @escaping () -> Void,
        spawnTerminal: @escaping (TerminalScope, _ command: String?) -> Void,
        newRemoteTerminal: @escaping () -> Bool = { false },
        closeRemoteTerminal: @escaping () -> Bool = { false },
        terminalSearch: @escaping () -> TerminalSearchStore? = { nil }
    ) {
        // Karar 103/108: ⌘T aktif terminal YÜZEYİNE vurur — repo route'unda o
        // checkout, All Terminals'ta geçerli konumda serbest terminal. Konum
        // çözümü `ShellContext.spawnTerminal(in:)`'in (top bar butonuyla aynı
        // kapı); `openSettings` deseniyle dışarıdan enjekte edilir.
        dispatcher.register(.newTerminal) {
            // Karar 143: Remote route'unda seçili uzak terminalin projesinde açar.
            if newRemoteTerminal() { return }
            guard let scope = shared.navigation.activeRoute.terminalScope else { return }
            // Provider terminali = shell + launch komutu
            spawnTerminal(scope, shared.settings.current.aiProvider.launchCommand)
        }
        // Electron paritesi: aktif terminal yoksa ⌘W repo TAB'ını kapatır
        // (karar 59). Tab kapanışı `requestCloseTab` guard'ından geçer —
        // minimize terminali olan tab dialog'suz kapanmaz.
        dispatcher.register(.closeTerminal) {
            // Karar 143: Remote route'unda seçili HUB terminalini kapatır; yerel
            // terminaller o route'ta görünmez, kapanmamalı.
            if closeRemoteTerminal() { return }
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
        // Karar 124: panel/popup kuralı `OrchestratorPresentation`'da; store
        // `SharedStores`'ta olmadığı için aksiyon dışarıdan enjekte edilir.
        dispatcher.register(.toggleOrchestrator, toggleOrchestrator)
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
        registerTerminalSearch(in: dispatcher, shared: shared, store: terminalSearch)
        dispatcher.register(.toggleLeftSidebar) { shared.layout.toggleSlot(.left) }
        dispatcher.register(.toggleRightSidebar) { shared.layout.toggleSlot(.right) }
        dispatcher.register(.toggleFocusMode) { shared.layout.toggleFocusMode() }
        dispatcher.register(.zoomIn) { shared.layout.zoomIn() }
        dispatcher.register(.zoomOut) { shared.layout.zoomOut() }
        dispatcher.register(.resetZoom) { shared.layout.resetZoom() }
        dispatcher.register(.openSettings, openSettings)
        dispatcher.register(.openAbout, openAbout)
        dispatcher.register(.checkForUpdates, checkForUpdates)
    }

    /// Karar 144: ⌘F / ⌘G / ⇧⌘G aktif terminal YÜZEYİNİN seçili terminaline
    /// vurur (⌃⌘M ile aynı hedef). Store `SharedStores`'ta olmadığı için
    /// dışarıdan enjekte edilir (`toggleOrchestrator` deseni).
    private static func registerTerminalSearch(
        in dispatcher: MenuActionDispatcher,
        shared: SharedStores,
        store: @escaping () -> TerminalSearchStore?
    ) {
        func target() -> TerminalID? {
            guard shared.navigation.activeRoute.terminalScope != nil,
                  let id = shared.terminals.activeTerminalID,
                  !shared.terminals.isMinimized(id) else { return nil }
            return id
        }
        dispatcher.register(.findInTerminal) {
            guard let id = target() else { return }
            store()?.open(id)
        }
        dispatcher.register(.findNextInTerminal) {
            guard let id = target() else { return }
            store()?.navigateFromShortcut(id, forward: true)
        }
        dispatcher.register(.findPreviousInTerminal) {
            guard let id = target() else { return }
            store()?.navigateFromShortcut(id, forward: false)
        }
    }
}
