import Foundation

/// Immutable-tree edits for the demo (ProjectNode/CheckoutNode are `let` structs).
extension ProjectNode {
    /// Adds `agent` to the checkout at `path` (or the root checkout); with a
    /// `workspace` name, to that workspace — created under the Lumi workspaces root.
    func demoAdding(agent id: String, at path: String, workspace: String?, branch: String?) -> ProjectNode {
        var checkouts = self.checkouts
        if let workspace {
            let wsPath = "\(DemoPaths.workspacesRoot)/\(name)/\(workspace)"
            if let index = checkouts.firstIndex(where: { $0.path == wsPath }) {
                checkouts[index] = checkouts[index].demoAdding(agent: id)
            } else {
                checkouts.append(CheckoutNode(kind: "workspace", title: workspace, branch: branch ?? workspace,
                                              scm: checkouts.first?.scm ?? "git", path: wsPath, agentIds: [id]))
            }
        } else if let index = checkouts.firstIndex(where: { $0.path == path })
                    ?? checkouts.firstIndex(where: { $0.kind == "original" }) {
            checkouts[index] = checkouts[index].demoAdding(agent: id)
        }
        return ProjectNode(name: name, path: self.path, checkouts: checkouts, appearance: appearance)
    }

    func demoRemoving(agent id: String) -> ProjectNode {
        ProjectNode(name: name, path: path, checkouts: checkouts.map { checkout in
            CheckoutNode(kind: checkout.kind, title: checkout.title, branch: checkout.branch, scm: checkout.scm,
                         path: checkout.path, agentIds: checkout.agentIds.filter { $0 != id })
        }, appearance: appearance)
    }
}

extension CheckoutNode {
    func demoAdding(agent id: String) -> CheckoutNode {
        CheckoutNode(kind: kind, title: title, branch: branch, scm: scm, path: path, agentIds: agentIds + [id])
    }
}
