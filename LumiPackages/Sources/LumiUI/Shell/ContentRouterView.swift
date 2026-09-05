import LumiKit
import SwiftUI

/// Orta alan router'ı (Faz 6.3).
///
/// `WorkspaceRoute` → descriptor eşlemesi burada biter; hangi terminalin
/// çizileceği, minimize şeridi ve boş-repo durumu route'un İÇ meselesidir
/// (`TerminalsRouteView`).
///
/// Route geçişinin yan etkileri (`detachAll` / `refreshAttachedViews` /
/// yüzey durumu) view'da DEĞİL `NavigationStore.setRoute`'tadır — bu view
/// yalnız o kararın sonucunu çizer.
struct ContentRouterView: View {
    let registry: ContentRouteRegistry

    @Shell private var shell

    var body: some View {
        switch shell.navigation.activeRoute {
        case .repo(let repoPath):
            routeView(.terminals, repoPath: repoPath)
        case .content(let id):
            routeView(id, repoPath: nil)
        case .none:
            WelcomeView()
        }
    }

    @ViewBuilder
    private func routeView(_ id: ContentRouteID, repoPath: String?) -> some View {
        if let descriptor = registry.resolve(id) {
            descriptor.makeView(repoPath)
        } else {
            WelcomeView()
        }
    }
}
