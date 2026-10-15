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
        // Karar 118: güncelleme kartı yığının EN ALTINDA — geçici toast'lar
        // kartın üstüne dizilir, onu örtmez (Orca `NotificationCardStack`).
        VStack(alignment: .trailing, spacing: 0) {
            ToastOverlay(store: shell.toasts) { terminalID in
                shell.terminals.restoreAndFocus(terminalID)
            }
            // Modal açıkken kart scrim'in üstünde kalmasın (onay dialogu dahil).
            if shell.appUpdate.isCardVisible, !shell.dialogs.isInputBlockingOverlayOpen {
                // Karar 118: pencerenin sağ alt köşesine sabit — hiçbir panele
                // bağlı değil (sağ yuva açılıp kapanınca yer değiştirmez).
                AppUpdateCard()
                    .padding([.horizontal, .bottom], Theme.Spacing.xl)
            }
        }
        .animation(Theme.Motion.standardOut, value: shell.appUpdate.isCardVisible)
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

/// Quit onayı (`.terminateLater` akışı — design/03 §2). Karar 118: native
/// `confirmationDialog` yerine Lumi'nin kendi dialogu.
public struct QuitDialogOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let count = shell.dialogs.quitDialogTerminalCount {
            ConfirmDialog(
                icon: "power",
                iconColor: Theme.error,
                title: "Quit Lumi?",
                message: Self.message(terminalCount: count),
                note: updateNote,
                cancel: .init(title: "Cancel") { shell.dialogs.resolveQuit(false) },
                actions: [.init(title: "Quit", kind: .destructive) { shell.dialogs.resolveQuit(true) }]
            )
        }
    }

    static func message(terminalCount: Int) -> String {
        let noun = terminalCount == 1 ? "terminal" : "terminals"
        return "Your \(terminalCount) open \(noun) will be closed and anything running in them will be stopped. "
            + "Claude and Codex sessions are resumed the next time you open Lumi."
    }

    /// Karar 118: `Install on Quit` seçiliyse quit'in ardından kurulacağı söylenir.
    private var updateNote: String? {
        guard shell.appUpdate.installTiming == .onQuit,
              let staged = shell.appUpdate.stagedUpdate
        else { return nil }
        return "Lumi \(staged.release.version.description) will be installed after quitting."
    }
}

/// Güncelleme onayı (karar 118): Cancel / Install on Quit / Restart Now.
///
/// Restart kapanıştır — terminaller ölür. Bu yüzden dialog kaç terminalin
/// kapanacağını açıkça söyler ve Restart terminal varken yıkıcı roldedir.
/// `Install on Quit` çalışmayı bölmez: kurulum kullanıcının kendi quit'inde
/// yapılır (yeniden açmadan). Bu yolla gelen quit, quit dialogunu atlar
/// (`DialogRouter.preconfirmQuit`).
public struct InstallUpdateDialogOverlay: View {
    @Shell private var shell

    public init() {}

    public var body: some View {
        if let state = shell.dialogs.installUpdateDialog {
            ConfirmDialog(
                icon: "arrow.down.circle",
                title: "Restart Lumi to install \(state.version)?",
                message: Self.message(terminalCount: state.terminalCount),
                note: state.isScheduledOnQuit
                    ? "The update is set to install the next time you quit Lumi."
                    : "Choose Install on Quit to keep working — the update is installed the next time you quit Lumi.",
                cancel: .init(title: "Cancel") { shell.resolveInstallUpdate(.cancel) },
                actions: [
                    .init(title: state.isScheduledOnQuit ? "Don't Install on Quit" : "Install on Quit") {
                        shell.resolveInstallUpdate(.toggleInstallOnQuit)
                    },
                    .init(title: "Restart Now", kind: state.terminalCount > 0 ? .destructive : .primary) {
                        shell.resolveInstallUpdate(.restartNow)
                    },
                ]
            )
        }
    }

    static func message(terminalCount: Int) -> String {
        var text = "Lumi will quit, install the update and reopen."
        if terminalCount > 0 {
            let noun = terminalCount == 1 ? "terminal" : "terminals"
            text += " Your \(terminalCount) open \(noun) will be closed and anything running in them "
                + "will be stopped. Claude and Codex sessions are resumed after the restart."
        }
        return text
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
