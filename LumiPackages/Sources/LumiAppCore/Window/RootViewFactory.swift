import AppKit
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// `RootView`'ın kurulumu ve servis-yüzlü aksiyonlarının bağlanması
/// (refactor 3.6 — `AppDelegate`'ten çıkarıldı).
///
/// View'lar servisleri asla görmez (design/00 §3): dosya/sistem etkileşimleri
/// buradaki closure'lardan geçer. Faz 6'da `RootView` `ShellContext`'e geçince
/// bu fabrika 14 parametreden 1'e iner.
@MainActor
struct RootViewFactory {
    private let composition: AppComposition

    init(composition: AppComposition) {
        self.composition = composition
    }

    private var registry: LiveServiceRegistry { composition.registry }
    private var shared: SharedStores { composition.shared }

    func makeRootView() -> RootView {
        RootView(
            workspace: shared.workspace,
            repoStore: composition.repo.repoStore,
            terminals: shared.terminals,
            promptQueue: composition.terminal.promptQueue,
            gitStore: composition.repo.gitStore,
            fileViewer: composition.repo.fileViewer,
            onboarding: composition.workspaceBoot.onboarding,
            settings: shared.settings,
            sessionSchedule: composition.sessionSchedule.sessionSchedule,
            usageStores: composition.usage.usageStores,
            toasts: shared.toasts,
            viewProvider: registry.viewProvider,
            highlighter: HighlightrEngine(),
            fileActions: makeFileActions(),
            shellActions: makeShellActions()
        )
    }

    /// Pencere içeriği: titlebar safe-area'sı kadar AŞAĞI itilmesin — y0'dan
    /// başlasın (v1 paritesi: header trafiğin hizasında, boşa giden üst bant yok).
    func makeContentView() -> NSView {
        let hosting = NSHostingView(rootView: makeRootView())
        hosting.safeAreaRegions = []
        return hosting
    }

    private func makeFileActions() -> RootView.FileActions {
        RootView.FileActions(
            reveal: { repoPath, relativePath in
                registry.system.revealInFinder(path: repoPath + "/" + relativePath)
            },
            trash: { repoPath, relativePath in
                Task { @MainActor in
                    await shared.toasts.reporting {
                        try await registry.system.trash(path: repoPath + "/" + relativePath)
                    }
                    await composition.repo.repoStore.loadFileTree(repoPath)
                }
            }
        )
    }

    private func makeShellActions() -> RootView.ShellActions {
        RootView.ShellActions(
            chooseFolder: { await registry.system.chooseFolder() }
        )
    }
}
