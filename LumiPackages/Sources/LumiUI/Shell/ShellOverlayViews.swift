import LumiKit
import LumiState
import SwiftUI

/// Overlay descriptor'larının `makeView`'leri parametre almaz (Faz 6.5), bu
/// yüzden her overlay bağlamını Environment'tan okuyan ince bir taşıyıcıya
/// sarılır. Taşıyıcılar `public`tir: kayıt composition root'ta yapılır.

/// Focus mode hover-reveal barı (route bir terminal yüzeyindeyken anlamlı —
/// repo ya da All Terminals, karar 103).
public struct FocusModeBarOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let scope = shell.activeTerminalScope {
            FocusModeBar(scope: scope)
        }
    }
}

public struct FileViewerOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        FileViewerView(store: shell.fileViewer, highlighter: shell.highlighter, markdownParser: shell.markdownParser)
    }
}

/// Repo seçici (karar 55). Eskiden top bar tab şeridindeki (+) butonunun
/// popover'ıydı; şerit kalkınca modal overlay'e taşındı. Seçim aktif tab'ı
/// açar, açık tab'lar listede gizlenir.
public struct RepoSelectorOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        ModalOverlay(onDismiss: { shell.dialogs.isRepoSelectorOpen = false }) {
            Panel(variant: .modal) {
                RepoSelectorView(
                    groups: shell.repos.groupedRepos,
                    // Karar 65: HİÇBİR ŞEY dışlanmaz. Eskiden açık tab'lar
                    // dışlanıyordu, yani açtığın bir repo'ya ⌘O ile geri
                    // dönemiyordun. Artık ⌘O hem ekler hem geçiş yapar.
                    excludedRepoPaths: [],
                    collapsedGroups: Binding(
                        get: { shell.dialogs.collapsedRepoGroups },
                        set: { shell.dialogs.collapsedRepoGroups = $0 }
                    )
                ) { repo in
                    shell.dialogs.isRepoSelectorOpen = false
                    Task { await shell.goToProject(repo) }
                }
            }
        }
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

    /// Karar 66: aynı dialog iki akışı taşır. Metin proje kaldırmada AÇIKÇA
    /// farklıdır — kaldırma kalıcı listeye dokunur ve projenin TÜM
    /// checkout'larını kapatır; "Close Tab" yazan bir buton bunu gizlerdi.
    private var isProject: Bool { shell.dialogs.closeTabDialog?.isProject ?? false }
    private var name: String { shell.dialogs.closeTabDialog?.repoName ?? "" }
    private var minimizedCount: Int { shell.dialogs.closeTabDialog?.minimizedCount ?? 0 }

    public var body: some View {
        DialogAnchor()
            .confirmationDialog(
                isProject ? "Remove \(name) from Projects?" : "Close \(name)?",
                isPresented: Binding(
                    get: { shell.dialogs.closeTabDialog != nil },
                    set: { if !$0 { shell.cancelCloseTab() } }
                )
            ) {
                Button(
                    isProject ? "Remove Project" : "Close Tab",
                    role: .destructive
                ) { shell.confirmCloseTab() }
                Button("Cancel", role: .cancel) { shell.cancelCloseTab() }
            } message: {
                Text(
                    isProject
                        ? "\(minimizedCount) minimized terminal across this project's checkouts will be killed."
                        : "\(minimizedCount) minimized terminal will be killed."
                )
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
