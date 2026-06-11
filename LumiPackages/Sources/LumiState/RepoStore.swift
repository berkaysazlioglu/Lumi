import Foundation
import LumiKit
import Observation

/// Repo listesi + kaynak bazlı gruplama (spec/21 §14-15).
/// Event → tam yeniden çekme (pull-after-push korunur).
@Observable
@MainActor
public final class RepoStore {
    public private(set) var repos: [Repo] = []
    /// Gruplamanın "boş root grupları da göster" kuralı için config sırasıyla tutulur.
    public var additionalPaths: [AdditionalPath] = []

    @ObservationIgnored private let service: any RepoServicing
    @ObservationIgnored private var consumeTask: Task<Void, Never>?

    public init(service: any RepoServicing) {
        self.service = service
    }

    public func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { @MainActor [weak self, service] in
            let stream = await service.events()
            await self?.reload()
            for await _ in stream {
                await self?.reload()
            }
        }
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    public func reload() async {
        repos = await service.repos()
    }

    public func repo(at path: String) -> Repo? {
        repos.first { $0.path == path }
    }

    // MARK: - Gruplama (spec/21 §15 — groupReposBySource paritesi)

    public struct RepoGroup: Identifiable, Equatable {
        public let id: String
        public let label: String
        public let repos: [Repo]
    }

    /// Sıra: (1) Projects Root (boşsa görünmez), (2) root-tipi additional path'ler
    /// config sırasıyla (BOŞ olsa bile görünür; label = verilen ya da path'in son
    /// segmenti), (3) Standalone Repos (boşsa görünmez).
    public var groupedRepos: [RepoGroup] {
        var groups: [RepoGroup] = []

        let rootRepos = repos.filter { $0.source == .projectsRoot }
        if !rootRepos.isEmpty {
            groups.append(RepoGroup(id: "__projects_root__", label: "Projects Root", repos: rootRepos))
        }

        for additional in additionalPaths where additional.type == .root {
            let members = repos.filter {
                if case .additionalRoot(let path, _) = $0.source {
                    return path == additional.path
                }
                return false
            }
            let label = additional.label ?? (additional.path as NSString).lastPathComponent
            groups.append(RepoGroup(id: additional.id, label: label, repos: members))
        }

        let standalone = repos.filter { $0.source == .standalone }
        if !standalone.isEmpty {
            groups.append(RepoGroup(id: "__standalone__", label: "Standalone Repos", repos: standalone))
        }

        return groups
    }
}
