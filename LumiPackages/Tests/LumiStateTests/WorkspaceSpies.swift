import Foundation
import LumiKit
@testable import LumiState

/// `TerminalFocusCoordinating` casusu — navigasyon/layout birim testleri
/// `TerminalListStore`'a bağlanmadan koşar (refactor 5.2 dar protokolünün
/// asıl kazancı budur).
@MainActor
final class SpyTerminalFocusCoordinator: TerminalFocusCoordinating {
    enum Call: Equatable {
        case activateRepo(String)
        case deactivateSurface
        case focus(TerminalID?)
        case closeAll(String)
    }

    var calls: [Call] = []
    var minimizedByRepo: [String: [TerminalMeta]] = [:]
    var visibleByRepo: [String: [TerminalMeta]] = [:]

    func activateRepo(_ repoPath: String) { calls.append(.activateRepo(repoPath)) }
    func deactivateSurface() { calls.append(.deactivateSurface) }
    func focus(_ id: TerminalID?) { calls.append(.focus(id)) }
    func closeAll(in repoPath: String) { calls.append(.closeAll(repoPath)) }

    func minimizedTerminals(in repoPath: String) -> [TerminalMeta] {
        minimizedByRepo[repoPath] ?? []
    }

    func visibleTerminals(in repoPath: String) -> [TerminalMeta] {
        visibleByRepo[repoPath] ?? []
    }
}

enum WorkspaceFixtures {
    static let repos = [
        Repo(name: "alpha", path: "/r/alpha", isGitRepo: true, source: .projectsRoot),
        Repo(name: "beta", path: "/r/beta", isGitRepo: true, source: .projectsRoot),
    ]

    static func uiState(
        openTabs: [String] = [],
        activeTab: String? = nil,
        leftSidebarOpen: Bool = true,
        rightSidebarOpen: Bool = false,
        projectGridLayouts: [String: GridLayout] = [:],
        legacyGridColumns: GridLayout? = nil
    ) -> UIState {
        UIState(
            openTabs: openTabs,
            activeTab: activeTab,
            leftSidebarOpen: leftSidebarOpen,
            rightSidebarOpen: rightSidebarOpen,
            projectGridLayouts: projectGridLayouts,
            windowBounds: nil,
            windowMaximized: nil,
            legacyGridColumns: legacyGridColumns
        )
    }

    static func meta(_ name: String, repo: String) -> TerminalMeta {
        TerminalMeta(id: TerminalID(), name: name, repoPath: repo, createdAt: Date())
    }
}
