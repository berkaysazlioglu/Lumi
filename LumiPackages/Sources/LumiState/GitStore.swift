import Foundation
import LumiKit
import Observation

/// Sağ sidebar'ın git veri cache'leri + commit akışı.
/// Tüm tazeleme fileTreeChanged event'i (container köprüsü) veya UI etkileşimiyle.
@Observable
@MainActor
public final class GitStore {
    /// Eşzamanlı `git log` tavanı (bkz. `loadCommits`).
    static let maxConcurrentBranchLoads = 4

    public private(set) var branches: [String: [GitBranch]] = [:]
    public private(set) var commitsByBranch: [String: [String: [GitCommit]]] = [:]
    public private(set) var changes: [String: [GitFileChange]] = [:]
    public private(set) var selectedFiles: [String: Set<String>] = [:]
    public var commitMessages: [String: String] = [:]
    public private(set) var isCommitting = false

    /// Branch accordion durumu: kullanıcı hiç toggle yapmadıysa current branch
    /// otomatik expand; toggle sonrası kullanıcının seçimi kalır.
    public private(set) var expandedBranches: [String: Set<String>] = [:]
    @ObservationIgnored private var userToggledRepos: Set<String> = []

    /// ISP (refactor 3.8): store yalnız sessiz-liste okumaları + commit yazımı
    /// yüzeyine bağlıdır; içerik/diff okumaları `FileViewerStore`'un işidir.
    @ObservationIgnored private let git: any GitReading & GitWriting
    @ObservationIgnored private let toasts: ToastStore

    public init(git: any GitReading & GitWriting, toasts: ToastStore) {
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

        commitsByBranch[repoPath] = await loadCommits(repoPath, branches: branchList)
    }

    /// Branch başına `git log` çağrısı — aynı anda en fazla
    /// `maxConcurrentBranchLoads` tanesi koşar. Sınırsız TaskGroup, çok branch'li
    /// repolarda her FSEvents tazelemesinde onlarca git süreci açıyordu.
    private func loadCommits(
        _ repoPath: String,
        branches branchList: [GitBranch]
    ) async -> [String: [GitCommit]] {
        await withTaskGroup(
            of: (String, [GitCommit]).self,
            returning: [String: [GitCommit]].self
        ) { [git] group in
            var pending = branchList.makeIterator()

            func addNext() -> Bool {
                guard let branch = pending.next() else { return false }
                group.addTask {
                    (branch.name, await git.commits(repoPath: repoPath, branch: branch.name))
                }
                return true
            }

            for _ in 0 ..< Self.maxConcurrentBranchLoads {
                guard addNext() else { break }
            }

            var result: [String: [GitCommit]] = [:]
            for await (name, list) in group {
                result[name] = list
                _ = addNext()
            }
            return result
        }
    }

    public func loadChanges(_ repoPath: String) async {
        let list = await git.status(repoPath: repoPath)
        changes[repoPath] = list
        // Select-all default: her status yüklemesinde sıfırlanır
        selectedFiles[repoPath] = Set(list.map(\.path))
    }

    /// fileTreeChanged köprüsü — git panellerinin canlılığı.
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

    // MARK: - Commit

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
