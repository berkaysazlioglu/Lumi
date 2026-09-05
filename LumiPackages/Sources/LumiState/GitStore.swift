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
    /// History graph'ının commit tavanı (karar 40): tek log, sabit pencere.
    public static let historyLimit = 200
    /// PR açılamayan branch'ler — bu branch'lerdeyken "Create PR" görünmez.
    static let defaultBranchNames: Set<String> = ["main", "master"]

    public private(set) var branches: [String: [GitBranch]] = [:]
    public private(set) var commitsByBranch: [String: [String: [GitCommit]]] = [:]
    /// Karar 40: `HEAD`ten geriye tek topolojik log — graph'ın kaynağı.
    public private(set) var history: [String: [GitCommit]] = [:]
    /// History'nin HEAD commit'i (`HEAD -> …` dekorasyonundan türer).
    public private(set) var headHash: [String: String] = [:]
    /// `origin` remote URL'i (ham); GitHub eylemlerinin kapısı.
    public private(set) var remoteURLs: [String: String] = [:]
    /// GitHub CLI PATH'te mi? Süreç ömrü boyunca bir kez ölçülür.
    public private(set) var isGitHubCLIAvailable = false
    @ObservationIgnored private var didProbeGitHubCLI = false
    public private(set) var changes: [String: [GitFileChange]] = [:]
    /// Karar 41: başlıktaki upstream / ahead-behind / satır istatistiği.
    public private(set) var branchSummaries: [String: GitBranchSummary] = [:]
    public private(set) var explorerStatuses: [String: [String: FileChangeStatus]] = [:]
    public private(set) var selectedFiles = KeyedToggleSet<String, String>()
    /// Commit mesajı taslakları (refactor 5.4 kapsülleme borcu kapandı):
    /// yazım YALNIZ `setCommitMessage(_:for:)` intent'inden geçer; view
    /// `commitMessage(for:)` ile okur.
    public private(set) var commitMessages: [String: String] = [:]
    public private(set) var isCommitting = false

    /// Branch accordion durumu: kullanıcı hiç toggle yapmadıysa current branch
    /// otomatik expand; toggle sonrası kullanıcının seçimi kalır.
    public private(set) var expandedBranches = KeyedToggleSet<String, String>()
    @ObservationIgnored private var userToggledRepos: Set<String> = []
    /// Kullanıcı bu repo'da seçimi en az bir kez elle değiştirdi mi? Değiştirdiyse
    /// tazeleme seçimi EZMEZ (bkz. `loadChanges`).
    @ObservationIgnored private var reposWithUserSelection: Set<String> = []

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
            expandedBranches.insert(current.name, in: repoPath)
        }

        await loadChanges(repoPath)
        await loadHistory(repoPath)

        commitsByBranch[repoPath] = await loadCommits(repoPath, branches: branchList)
    }

    /// Graph history + remote bağlamı. `gh` yoklaması yalnız İLK çağrıda
    /// koşar: PATH taraması repo'dan bağımsızdır ve her tazelemede bir
    /// `which gh` süreci açmak gereksiz.
    public func loadHistory(_ repoPath: String) async {
        let commits = await git.history(repoPath: repoPath, limit: Self.historyLimit)
        history[repoPath] = commits
        if let head = commits.first(where: { commit in
            commit.references.contains { $0.isCurrent || $0.kind == .head }
        }) {
            headHash[repoPath] = head.hash
        } else {
            headHash[repoPath] = commits.first?.hash
        }

        if let remote = await git.remoteURL(repoPath: repoPath) {
            remoteURLs[repoPath] = remote
        } else {
            remoteURLs.removeValue(forKey: repoPath)
        }

        if !didProbeGitHubCLI {
            didProbeGitHubCLI = true
            isGitHubCLIAvailable = await git.isGitHubCLIAvailable()
        }
    }

    // MARK: - GitHub türevleri (karar 40)

    /// Commit'in GitHub web adresi — remote GitHub değilse nil (eylem gizlenir).
    public func commitURL(_ repoPath: String, sha: String) -> URL? {
        guard let remote = remoteURLs[repoPath] else { return nil }
        return GitRemote.commitURL(from: remote, sha: sha)
    }

    public func isGitHubRepo(_ repoPath: String) -> Bool {
        remoteURLs[repoPath].map(GitRemote.isGitHub) ?? false
    }

    /// "Create PR" kapısı: GitHub remote + `gh` kurulu + default branch DIŞINDA
    /// bir branch checkout edilmiş olmalı.
    public func pullRequestBranch(_ repoPath: String) -> String? {
        guard isGitHubRepo(repoPath) else { return nil }
        guard let current = branches[repoPath]?.first(where: { $0.isCurrent }) else { return nil }
        guard !Self.defaultBranchNames.contains(current.name) else { return nil }
        return current.name
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

    /// Tazeleme kuralı (Faz 5 bug fix'i): kullanıcı bu repo'da seçime hiç
    /// DOKUNMADIYSA select-all default'u sürer. Bir kez toggle ettiyse seçim
    /// KORUNUR — yalnız artık var olmayan dosyalar düşer, yeni görünen dosyalar
    /// kendiliğinden SEÇİLMEZ. Önceki davranışta her FSEvents tazelemesi
    /// deselect'i geri alıyordu ve commit ekranında istenmeyen dosya stage
    /// edilme riski doğuyordu.
    public func loadChanges(_ repoPath: String) async {
        let list = await git.status(repoPath: repoPath)
        changes[repoPath] = list
        explorerStatuses[repoPath] = ExplorerGitDecoration.statuses(list)
        if let summary = await git.branchSummary(repoPath: repoPath) {
            branchSummaries[repoPath] = summary
        } else {
            branchSummaries.removeValue(forKey: repoPath)
        }
        let present = Set(list.map(\.path))
        if reposWithUserSelection.contains(repoPath) {
            selectedFiles.replace((selectedFiles[repoPath] ?? []).intersection(present), in: repoPath)
        } else {
            selectedFiles.replace(present, in: repoPath)
        }
    }

    /// fileTreeChanged köprüsü — git panellerinin canlılığı.
    public func refresh(_ repoPath: String) async {
        await loadAll(repoPath)
    }

    // MARK: - Seçim / accordion

    public func toggleFile(_ repoPath: String, path: String) {
        reposWithUserSelection.insert(repoPath)
        selectedFiles.toggle(path, in: repoPath)
    }

    public func toggleSelectAll(_ repoPath: String) {
        reposWithUserSelection.insert(repoPath)
        let all = Set((changes[repoPath] ?? []).map(\.path))
        let current = selectedFiles[repoPath] ?? []
        selectedFiles.replace(current.count == all.count ? [] : all, in: repoPath)
    }

    public func isSelected(_ repoPath: String, path: String) -> Bool {
        selectedFiles.contains(path, in: repoPath)
    }

    public func toggleBranch(_ repoPath: String, name: String) {
        userToggledRepos.insert(repoPath)
        expandedBranches.toggle(name, in: repoPath)
    }

    public func isBranchExpanded(_ repoPath: String, name: String) -> Bool {
        expandedBranches.contains(name, in: repoPath)
    }

    // MARK: - Cache eviction (refactor 5.5)

    /// Tab kapanınca repo'ya ait TÜM bellek cache'leri boşaltılır — aksi halde
    /// açılıp kapanan her repo commit/branch/diff verisini kalıcı olarak
    /// bellekte bırakıyordu.
    public func evict(_ repoPath: String) {
        branches.removeValue(forKey: repoPath)
        commitsByBranch.removeValue(forKey: repoPath)
        history.removeValue(forKey: repoPath)
        headHash.removeValue(forKey: repoPath)
        remoteURLs.removeValue(forKey: repoPath)
        changes.removeValue(forKey: repoPath)
        branchSummaries.removeValue(forKey: repoPath)
        explorerStatuses.removeValue(forKey: repoPath)
        commitMessages.removeValue(forKey: repoPath)
        selectedFiles.evict(repoPath)
        expandedBranches.evict(repoPath)
        userToggledRepos.remove(repoPath)
        reposWithUserSelection.remove(repoPath)
    }

    // MARK: - Commit

    /// Commit butonunun kapısı (refactor 6.7): eskiden `GitChangesPanelItem`
    /// içinde view kuralıydı. En az bir dosya seçili, mesaj boşluk-dışı dolu ve
    /// uçuşta commit yok. `commit(_:)` aynı üç koşulu guard'lar — buton görünürde
    /// kapalıyken bile (Enter tuşu) sözleşme bozulmaz.
    public func canCommit(_ repoPath: String) -> Bool {
        guard !isCommitting else { return false }
        guard !(selectedFiles[repoPath] ?? []).isEmpty else { return false }
        return !commitMessage(for: repoPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    // MARK: - Commit mesajı (kapsülleme, refactor 5.4)

    public func commitMessage(for repoPath: String) -> String {
        commitMessages[repoPath] ?? ""
    }

    public func setCommitMessage(_ message: String, for repoPath: String) {
        commitMessages[repoPath] = message
    }

    public func commit(_ repoPath: String) async {
        guard canCommit(repoPath) else { return }
        let files = Array(selectedFiles[repoPath] ?? []).sorted()
        let message = commitMessage(for: repoPath).trimmingCharacters(in: .whitespacesAndNewlines)

        isCommitting = true
        defer { isCommitting = false }

        let succeeded = await toasts.reporting {
            try await self.git.commit(repoPath: repoPath, message: message, files: files)
        }
        if succeeded {
            setCommitMessage("", for: repoPath)
            await loadAll(repoPath)
        }
    }
}
