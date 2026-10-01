import LumiKit
import LumiState
import SwiftUI

/// Hızlı komutların çalışacağı checkout (karar 92/93) — komut, yer ve
/// `{path}`/`{branch}` anahtarlarının değerleri tek yerde çözülür.
@MainActor
struct QuickCommandTarget {
    let projectPath: String
    let context: QuickCommandContext
    /// Diski silinmiş workspace: komut çalıştırılamaz, yönetim açık kalır.
    let isMissing: Bool

    init(checkout: Checkout, shell: ShellContext) {
        let branch = checkout.identity(in: shell).branch ?? ""
        switch checkout {
        case .original(let repo):
            projectPath = repo.path
            context = QuickCommandContext(path: repo.path, projectPath: repo.path, name: repo.name, branch: branch)
            isMissing = false
        case .workspace(let workspace):
            projectPath = workspace.projectPath
            context = QuickCommandContext(
                path: workspace.path, projectPath: workspace.projectPath, name: workspace.name, branch: branch
            )
            isMissing = shell.workspaces.isMissing(workspace)
        }
    }

    /// Aktif sekmedeki checkout; Projects'te karşılığı yoksa `nil`.
    static func active(in shell: ShellContext) -> QuickCommandTarget? {
        guard let path = shell.activeRepoPath,
              let checkout = Checkout.resolve(path: path, shell: shell) else { return nil }
        return QuickCommandTarget(checkout: checkout, shell: shell)
    }
}

/// Top bar'daki hızlı komut kontrolünün içeriği (karar 96 — Orca `Run`
/// split-button paritesi). Mantık karar 92/93'tekiyle aynıdır; değişen yalnız
/// yeridir: Start App birincil butondur, diğer komutlar + yönetim açılır listede.
@MainActor
enum QuickCommandMenu {
    static func startApp(target: QuickCommandTarget, shell: ShellContext) -> ProjectQuickCommand? {
        shell.quickCommands.startApp(for: target.projectPath)
    }

    static func runStartApp(_ command: ProjectQuickCommand, target: QuickCommandTarget, shell: ShellContext) {
        let context = target.context
        Task { await shell.startApp(command, context: context) }
    }

    /// Açılır liste: komutlar (yeni terminalde) + `Add/Manage Actions…`.
    static func items(target: QuickCommandTarget, shell: ShellContext) -> [PopoverMenu.Item] {
        let actions = shell.quickCommands.actions(for: target.projectPath)
        let runs: [PopoverMenu.Item] = actions.map { command in
            .action(command.name, icon: "play", isEnabled: !target.isMissing) {
                let context = target.context
                Task { await shell.runQuickCommand(command, context: context) }
            }
        }
        let projectPath = target.projectPath
        let manage = PopoverMenu.Item.action(
            actions.isEmpty ? "Add Action…" : "Manage Actions…", icon: "slider.horizontal.3"
        ) {
            shell.dialogs.present(.quickCommands(projectPath: projectPath))
        }
        return runs + (runs.isEmpty ? [] : [.divider]) + [manage]
    }
}

extension Checkout {
    /// Bir sekme yolunun Projects'teki checkout'u: projenin kendisi ya da
    /// yönetilen bir workspace.
    @MainActor
    static func resolve(path: String, shell: ShellContext) -> Checkout? {
        if let workspace = shell.workspaces.records.first(where: { $0.path == path }) {
            return .workspace(workspace)
        }
        return shell.repos.repo(at: path).map(Checkout.original)
    }

    /// Original checkout da yönetilen workspace'lerle aynı iki kolonlu
    /// kimliği kullanır: solda sabit `main`, yanında gerçek SCM branch yolu.
    @MainActor
    func identity(in shell: ShellContext) -> CheckoutIdentity {
        switch self {
        case .original(let repo):
            if let branch = shell.git.branches[repo.path]?.first(where: { $0.isCurrent }) {
                return identity(originalBranch: branch.name)
            }
            if let branch = shell.plastic.workspaces[repo.path]?.branch {
                return identity(originalBranch: PlasticBranchName.display(branch))
            }
            return identity()
        case .workspace:
            return identity()
        }
    }
}
