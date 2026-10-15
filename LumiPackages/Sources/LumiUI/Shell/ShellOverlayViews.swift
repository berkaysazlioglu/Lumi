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
    /// Karar 118: kartın sağ paneli örtmemesi için yuvanın gerçekten çizilip
    /// çizilmediği (öğeleri çözülüyor mu) buradan okunur. `weak`: kayıt
    /// defteri bu view'ı üreten closure'ı tutar.
    private weak var registries: ShellRegistries?

    public init(registries: ShellRegistries? = nil) {
        self.registries = registries
    }

    /// Sağ yuva açıksa kart onun soluna oturur — kalıcı bir kart Source
    /// Control'ün Commit butonunu örtmesin. Geçici toast'lar köşede kalır.
    private var cardTrailingInset: CGFloat {
        guard let registries, shell.layout.isSlotVisible(.right),
              !registries.panels.resolved(slot: .right, layout: shell.layout.panelLayout, context: shell).isEmpty
        else { return 0 }
        return CGFloat(shell.layout.width(for: .right))
    }

    public var body: some View {
        // Karar 118: güncelleme kartı yığının EN ALTINDA — geçici toast'lar
        // kartın üstüne dizilir, onu örtmez (Orca `NotificationCardStack`).
        VStack(alignment: .trailing, spacing: 0) {
            ToastOverlay(store: shell.toasts) { terminalID in
                shell.terminals.restoreAndFocus(terminalID)
            }
            if shell.appUpdate.isCardVisible {
                AppUpdateCard()
                    .padding([.horizontal, .bottom], Theme.Spacing.xl)
                    .padding(.trailing, cardTrailingInset)
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
                Text(message)
            }
    }

    /// Karar 118: `Install on Quit` seçiliyse quit'in ardından kurulacağı söylenir.
    private var message: String {
        let terminals = "\(shell.dialogs.quitDialogTerminalCount ?? 0) open terminal(s) will be closed."
        guard shell.appUpdate.installTiming == .onQuit,
              let staged = shell.appUpdate.stagedUpdate
        else { return terminals }
        return terminals + " Lumi \(staged.release.version.description) will be installed after quitting."
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

    private var state: InstallUpdateDialogState? { shell.dialogs.installUpdateDialog }

    public var body: some View {
        DialogAnchor()
            .confirmationDialog(
                "Restart Lumi to install \(state?.version ?? "")?",
                isPresented: Binding(
                    get: { state != nil },
                    set: { if !$0 { shell.resolveInstallUpdate(.cancel) } }
                )
            ) {
                Button(
                    "Restart Now",
                    role: (state?.terminalCount ?? 0) > 0 ? .destructive : nil
                ) { shell.resolveInstallUpdate(.restartNow) }
                Button(state?.isScheduledOnQuit == true ? "Don't Install on Quit" : "Install on Quit") {
                    shell.resolveInstallUpdate(.toggleInstallOnQuit)
                }
                Button("Cancel", role: .cancel) { shell.resolveInstallUpdate(.cancel) }
            } message: {
                Text(Self.message(terminalCount: state?.terminalCount ?? 0))
            }
    }

    static func message(terminalCount: Int) -> String {
        var lines = ["Lumi will quit, install the update and reopen."]
        if terminalCount > 0 {
            let noun = terminalCount == 1 ? "terminal" : "terminals"
            lines.append(
                "Your \(terminalCount) open \(noun) will be closed and anything running in them "
                    + "will be stopped. Claude and Codex sessions are resumed after the restart."
            )
        }
        lines.append("Choose Install on Quit to keep working — the update is installed the next time you quit Lumi.")
        return lines.joined(separator: "\n\n")
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
