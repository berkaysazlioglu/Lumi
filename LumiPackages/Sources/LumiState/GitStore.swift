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

    /// Tazeleme kuralı (Faz 5 bug fix'i): kullanıcı bu repo'da seçime hiç
    /// DOKUNMADIYSA select-all default'u sürer. Bir kez toggle ettiyse seçim
    /// KORUNUR — yalnız artık var olmayan dosyalar düşer, yeni görünen dosyalar
    /// kendiliğinden SEÇİLMEZ. Önceki davranışta her FSEvents tazelemesi
    /// deselect'i geri alıyordu ve commit ekranında istenmeyen dosya stage
    /// edilme riski doğuyordu.
    public func loadChanges(_ repoPath: String) async {
        let list = await git.status(repoPath: repoPath)
        changes[repoPath] = list
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
        changes.removeValue(forKey: repoPath)
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
