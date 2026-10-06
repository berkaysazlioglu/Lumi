import Foundation
import LumiKit

/// Karar 115: bir senkron turunun config'e uygulanacak sonucu.
public struct WorktreeSyncPlan: Equatable, Sendable {
    /// Yönetilen kökte keşfedilen, henüz kaydı olmayan worktree'ler.
    public var additions: [ProjectWorkspace] = []
    /// Klasörü gitmiş ve canlı terminali olmayan kayıtların yolları.
    public var removals: [String] = []
    /// Kayıt yolu → git'in bildirdiği güncel dal.
    public var branchUpdates: [String: String] = [:]
    /// Klasörü gitmiş ama canlı terminali olduğu için tutulan kayıtlar.
    public var missingPaths: Set<String> = []

    public init() {}

    public var changesRecords: Bool { !additions.isEmpty || !removals.isEmpty || !branchUpdates.isEmpty }
}

/// Karar 115'in saf kuralı (Orca `mergeWorktree` + kaldırılan satır temizliği
/// paritesi). Girdi diskten ve git'ten önceden toplanır; burada I/O yoktur.
public enum WorktreeReconciler {
    /// Bir kaydın diskteki durumu — kanonik yol ve varlık ana thread dışında
    /// hesaplanır.
    public struct RecordState: Sendable, Equatable {
        public let record: ProjectWorkspace
        public let canonicalPath: String
        public let exists: Bool

        public init(record: ProjectWorkspace, canonicalPath: String, exists: Bool) {
            self.record = record
            self.canonicalPath = canonicalPath
            self.exists = exists
        }
    }

    /// - Parameters:
    ///   - listings: Proje yolu → git'in listesi. YALNIZ başarılı sorgular
    ///     girer; hatalı projede hiçbir şey eklenmez ve güncellenmez.
    ///   - liveCheckoutPaths: Canlı terminali olan checkout yolları.
    ///   - protectedPaths: Bu turda dokunulmayacak kayıtlar (oluşturulmakta
    ///     ya da silinmekte olanlar).
    ///   - sidebarProjectPaths: Kendisi proje olarak eklenmiş yollar
    ///     workspace olarak tekrar listelenmez.
    public static func plan(
        records: [RecordState],
        listings: [String: [GitWorktreeEntry]],
        liveCheckoutPaths: Set<String>,
        protectedPaths: Set<String> = [],
        sidebarProjectPaths: Set<String> = []
    ) -> WorktreeSyncPlan {
        var plan = WorktreeSyncPlan()
        for state in records where !state.exists && !protectedPaths.contains(state.record.path) {
            if liveCheckoutPaths.contains(state.record.path) {
                plan.missingPaths.insert(state.record.path)
            } else {
                plan.removals.append(state.record.path)
            }
        }
        let byCanonical = Dictionary(records.map { ($0.canonicalPath, $0) }, uniquingKeysWith: { first, _ in first })
        for projectPath in listings.keys.sorted() {
            for entry in listings[projectPath] ?? [] where entry.isListable {
                if let state = byCanonical[entry.path] {
                    if state.exists, state.record.scm == .git, let branch = entry.branch, branch != state.record.branch {
                        plan.branchUpdates[state.record.path] = branch
                    }
                    continue
                }
                guard entry.isInsideManagedRoot, !sidebarProjectPaths.contains(entry.path) else { continue }
                plan.additions.append(ProjectWorkspace(
                    projectPath: projectPath, path: entry.path, name: entry.folderName,
                    branch: entry.branch ?? "", scm: .git
                ))
            }
        }
        return plan
    }
}
