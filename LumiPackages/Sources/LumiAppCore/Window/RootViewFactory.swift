import AppKit
import LumiKit
import LumiState
import LumiUI
import SwiftUI

/// `RootView`'ın kurulumu (refactor 3.6 — `AppDelegate`'ten çıkarıldı).
///
/// Faz 6.1 sonrası fabrika 15 parametre yerine TEK enjeksiyon yapar:
/// kayıt defterini `RootView`'a, `ShellContext`'i Environment'a koyar. Store
/// grafiği ve servis-yüzlü aksiyonlar `ShellComposition`'da kurulur.
@MainActor
struct RootViewFactory {
    private let composition: AppComposition

    init(composition: AppComposition) {
        self.composition = composition
    }

    func makeRootView() -> some View {
        RootView(registries: composition.shell.registries)
            .environment(\.shell, composition.shell.context)
    }

    /// Pencere içeriği: titlebar safe-area'sı kadar AŞAĞI itilmesin — y0'dan
    /// başlasın (v1 paritesi: header trafiğin hizasında, boşa giden üst bant yok).
    func makeContentView() -> NSView {
        let hosting = NSHostingView(rootView: makeRootView())
        hosting.safeAreaRegions = []
        return hosting
    }
}
