import Foundation
import LumiKit
import Observation

/// Sağ sidebar'ın git veri cache'leri + commit akışı (spec/21 §16, spec/12 §5).
/// Tüm tazeleme fileTreeChanged event'i (container köprüsü) veya UI etkileşimiyle.
@Observable
@MainActor
public final class GitStore {
    public private(set) var branches: [String: [GitBranch]] = [:]
    public private(set) var commitsByBranch: [String: [String: [GitCommit]]] = [:]
    public private(set) var changes: [String: [GitFileChange]] = [:]
    public private(set) var selectedFiles: [String: Set<String>] = [:]
    public var commitMessages: [String: String] = [:]
    public private(set) var isCommitting = false

    /// Branch accordion durumu: kullanıcı hiç toggle yapmadıysa current branch
    /// otomatik expand (spec/12 §3); toggle sonrası kullanıcının seçimi kalır.
    public private(set) var expandedBranches: [String: Set<String>] = [:]
    @ObservationIgnored private var userToggledRepos: Set<String> = []

    @ObservationIgnored private let git: any GitServicing
    @ObservationIgnored private let toasts: ToastStore

    public init(git: any GitServicing, toasts: ToastStore) {
        self.git = git
        self.toasts = toasts
    }

    // MARK: - Yükleme

    public func loadAll(_ repoPath: String) async {
        let branchList = await git.branches(repoPath: repoPath)
        branches[repoPath] = branchList
        if !userToggledRepos.contains(repoPath),
           let current = branchList.first(where: { $0.isCurrent }) {
            expandedBranches[repoPath, default: []].insert(current.name)
        }

        await loadChanges(repoPath)

        let commits = await withTaskGroup(
            of: (String, [GitCommit]).self,
            returning: [String: [GitCommit]].self
        ) { [git] group in
            for branch in branchList {
                group.addTask {
                    (branch.name, await git.commits(repoPath: repoPath, branch: branch.name))
                }
            }
            var result: [String: [GitCommit]] = [:]
            for await (name, list) in group {
                result[name] = list
            }
            return result
        }
        commitsByBranch[repoPath] = commits
    }

    public func loadChanges(_ repoPath: String) async {
        let list = await git.status(repoPath: repoPath)
        changes[repoPath] = list
        // Select-all default (spec/12 §5): her status yüklemesinde sıfırlanır
        selectedFiles[repoPath] = Set(list.map(\.path))
    }

    /// fileTreeChanged köprüsü — git panellerinin canlılığı (spec/12 §12).
    public func refresh(_ repoPath: String) async {
        await loadAll(repoPath)
    }

    // MARK: - Seçim / accordion

    public func toggleFile(_ repoPath: String, path: String) {
        var selection = selectedFiles[repoPath] ?? []
        if selection.contains(path) {
            selection.remove(path)
        } else {
            selection.insert(path)
        }
        selectedFiles[repoPath] = selection
    }

    public func toggleSelectAll(_ repoPath: String) {
        let all = Set((changes[repoPath] ?? []).map(\.path))
        let current = selectedFiles[repoPath] ?? []
        selectedFiles[repoPath] = current.count == all.count ? [] : all
    }

    public func isSelected(_ repoPath: String, path: String) -> Bool {
        selectedFiles[repoPath]?.contains(path) ?? false
    }

    public func toggleBranch(_ repoPath: String, name: String) {
        userToggledRepos.insert(repoPath)
        var expanded = expandedBranches[repoPath] ?? []
        if expanded.contains(name) {
            expanded.remove(name)
        } else {
            expanded.insert(name)
        }
        expandedBranches[repoPath] = expanded
    }

    public func isBranchExpanded(_ repoPath: String, name: String) -> Bool {
        expandedBranches[repoPath]?.contains(name) ?? false
    }

    // MARK: - Commit (spec/12 §5)

    public var canCommit: Bool {
        !isCommitting
    }

    public func commit(_ repoPath: String) async {
        let files = Array(selectedFiles[repoPath] ?? []).sorted()
        let message = (commitMessages[repoPath] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !files.isEmpty, !message.isEmpty, !isCommitting else { return }

        isCommitting = true
        defer { isCommitting = false }

        let succeeded = await toasts.reporting {
            try await self.git.commit(repoPath: repoPath, message: message, files: files)
        }
        if succeeded {
            commitMessages[repoPath] = ""
            await loadAll(repoPath)
        }
    }
}
