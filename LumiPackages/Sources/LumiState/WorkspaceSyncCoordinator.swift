import Foundation
import LumiKit

/// Karar 115: Projects panelinin checkout listesini git ve diskle eşitler
/// (Orca paritesi).
///
/// Bir tur: sidebar'daki Git projelerinin `git worktree list`'i + kayıtların
/// diskteki varlığı → `WorktreeReconciler` planı → `ProjectWorkspaceStore`.
/// Tetikleyiciler (dizin izleyicisi, uygulamanın öne gelmesi, proje listesi
/// değişimi, terminal kapanışı) `requestSync()`'e iner; uçuştaki tur varken
/// gelen istekler tek bir takip turuna çöker.
@MainActor
public final class WorkspaceSyncCoordinator {
    private let discovery: any WorktreeDiscovering
    private let workspaces: ProjectWorkspaceStore
    private let liveCheckoutPaths: @MainActor () -> Set<String>
    private var isRunning = false
    private var isPending = false
    private var changeListener: Task<Void, Never>?
    private var runner: Task<Void, Never>?

    public init(
        discovery: any WorktreeDiscovering,
        workspaces: ProjectWorkspaceStore,
        liveCheckoutPaths: @escaping @MainActor () -> Set<String>
    ) {
        self.discovery = discovery
        self.workspaces = workspaces
        self.liveCheckoutPaths = liveCheckoutPaths
    }

    /// İzleyici sinyallerini dinlemeye başlar ve ilk turu ister.
    public func start() {
        guard changeListener == nil else { return }
        let stream = discovery.changes()
        changeListener = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                self.requestSync()
            }
        }
        requestSync()
    }

    public func stop() {
        changeListener?.cancel()
        changeListener = nil
        runner?.cancel()
        runner = nil
        isRunning = false
        isPending = false
    }

    public func requestSync() {
        guard !isRunning else {
            isPending = true
            return
        }
        isRunning = true
        runner = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.isPending = false
                await self.sync()
            } while self.isPending && !Task.isCancelled
            self.isRunning = false
        }
    }

    /// Terminal listesi değişti: yalnız canlı terminal yüzünden tutulan
    /// (`Missing`) kayıt varken anlamlıdır — son terminal kapanınca düşer.
    public func terminalsChanged() {
        guard !workspaces.missingWorkspacePaths.isEmpty else { return }
        requestSync()
    }

    /// Bir turu sonuna kadar koşar (testler ve `requestSync` döngüsü).
    public func sync() async {
        let projects = workspaces.addedProjects.filter(\.isGitRepo).map(\.path)
        let listings = await list(projects)
        let states = await Self.recordStates(workspaces.records)
        let plan = WorktreeReconciler.plan(
            records: states,
            listings: listings,
            liveCheckoutPaths: liveCheckoutPaths(),
            protectedPaths: workspaces.syncProtectedPaths,
            sidebarProjectPaths: Set(workspaces.sidebarProjectPaths)
        )
        await workspaces.applySync(plan, listings: listings)
        await discovery.watch(projectPaths: projects, checkoutPaths: workspaces.records.map(\.path))
    }

    /// Hatalı proje sonuçtan düşer: o projede hiçbir şey eklenmez/güncellenmez.
    private func list(_ projects: [String]) async -> [String: [GitWorktreeEntry]] {
        let discovery = discovery
        return await withTaskGroup(of: (String, [GitWorktreeEntry]?).self) { group in
            for project in projects {
                group.addTask { (project, try? await discovery.worktrees(projectPath: project)) }
            }
            var listings: [String: [GitWorktreeEntry]] = [:]
            for await (project, entries) in group {
                if let entries { listings[project] = entries }
            }
            return listings
        }
    }

    /// Kanonik yol + varlık dosya sistemine dokunur; ana thread'de koşmaz.
    private static func recordStates(_ records: [ProjectWorkspace]) async -> [WorktreeReconciler.RecordState] {
        await Task.detached(priority: .utility) {
            records.map { record in
                var directory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: record.path, isDirectory: &directory) && directory.boolValue
                return WorktreeReconciler.RecordState(
                    record: record, canonicalPath: CanonicalPath.of(record.path), exists: exists
                )
            }
        }.value
    }
}
