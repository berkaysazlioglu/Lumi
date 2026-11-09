import Foundation
import LumiKit

/// Checkout'un kullanıcıya görünen adı: proje kökü için proje adı, yönetilen
/// workspace için `proje / workspace` (Projects panelindeki hiyerarşinin tek
/// satırlık hâli), serbest terminal için kısa yol (karar 108).
///
/// Kart etiketi (`ShellContext.checkoutLabel`) ve bildirim alt başlığı
/// (karar 145) aynı kuralı kullanır.
@MainActor
public enum CheckoutLabel {
    public static func make(
        for repoPath: String,
        workspaces: ProjectWorkspaceStore,
        repos: RepoStore,
        navigation: NavigationStore
    ) -> String {
        if let workspace = workspaces.records.first(where: { $0.path == repoPath }) {
            return "\(projectName(at: workspace.projectPath, repos: repos)) / \(workspace.name)"
        }
        if let repo = repos.repo(at: repoPath) { return repo.name }
        // Serbest terminalin "checkout"u bir proje değil, dizindir — klasör adı
        // (`Desktop`) yerine kısa yol (`~/Desktop`).
        if navigation.isLooseTerminalPath(repoPath) {
            return LooseTerminalPath.displayLabel(repoPath)
        }
        return projectName(at: repoPath, repos: repos)
    }

    public static func projectName(at path: String, repos: RepoStore) -> String {
        repos.repo(at: path)?.name ?? (path as NSString).lastPathComponent
    }
}
