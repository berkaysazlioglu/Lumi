import LumiKit
import LumiState
import SwiftUI

/// Overlay descriptor'larının `makeView`'leri parametre almaz (Faz 6.5), bu
/// yüzden her overlay bağlamını Environment'tan okuyan ince bir taşıyıcıya
/// sarılır. Taşıyıcılar `public`tir: kayıt composition root'ta yapılır.

/// Focus mode hover-reveal barı (route repo eksenindeyken anlamlı).
public struct FocusModeBarOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let repoPath = shell.activeRepoPath {
            FocusModeBar(repoPath: repoPath)
        }
    }
}

public struct FileViewerOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        FileViewerView(store: shell.fileViewer, highlighter: shell.highlighter)
    }
}

public struct SettingsOverlay: View {
    public init() {}

    public var body: some View {
        SettingsShell()
    }
}

public struct ToastOverlayHost: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        ToastOverlay(store: shell.toasts) { terminalID in
            shell.terminals.restoreAndFocus(terminalID)
        }
    }
}

/// Close-tab guard'ı. `confirmationDialog` bir modifier olduğu için sıfır
/// boyutlu, hit-test'siz bir taşıyıcıya takılır — overlay yığını içinde
/// altındaki içeriği bloklamaz.
public struct CloseTabDialogOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        DialogAnchor()
            .confirmationDialog(
                "Close \(shell.dialogs.closeTabDialog?.repoName ?? "")?",
                isPresented: Binding(
                    get: { shell.dialogs.closeTabDialog != nil },
                    set: { if !$0 { shell.cancelCloseTab() } }
                )
            ) {
                Button("Close Tab", role: .destructive) { shell.confirmCloseTab() }
                Button("Cancel", role: .cancel) { shell.cancelCloseTab() }
            } message: {
                Text("\(shell.dialogs.closeTabDialog?.minimizedCount ?? 0) minimized terminal will be killed.")
            }
    }
}

/// Quit onayı (`.terminateLater` akışı — design/03 §2).
public struct QuitDialogOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        DialogAnchor()
            .confirmationDialog(
                "Quit Lumi?",
                isPresented: Binding(
                    get: { shell.dialogs.quitDialogTerminalCount != nil },
                    set: { isPresented in
                        if !isPresented, shell.dialogs.quitDialogTerminalCount != nil {
                            shell.dialogs.resolveQuit(false)
                        }
                    }
                )
            ) {
                Button("Quit", role: .destructive) { shell.dialogs.resolveQuit(true) }
                Button("Cancel", role: .cancel) { shell.dialogs.resolveQuit(false) }
            } message: {
                Text("\(shell.dialogs.quitDialogTerminalCount ?? 0) open terminal(s) will be closed.")
            }
    }
}

/// Dialog modifier'larının bağlandığı görünmez çapa.
private struct DialogAnchor: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }
}
