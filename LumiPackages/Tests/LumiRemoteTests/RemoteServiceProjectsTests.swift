import Testing
import Foundation
import LumiKit
import LumiTestSupport
@testable import LumiRemote

// MARK: - FakeRelayConnection projects helpers

extension FakeRelayConnection {
    /// `projects` frame'indeki proje path'leri (Sendable [String] döner).
    func projectPaths() -> [String] {
        guard let payload = sent.first(where: { $0.type == "projects" })?.payload,
              let list = payload["projects"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["path"] as? String }
    }

    /// `projects` frame'indeki ilk projenin ilk checkout kind'ı (Sendable String? döner).
    func firstCheckoutKind() -> String? {
        guard let payload = sent.first(where: { $0.type == "projects" })?.payload,
              let list = payload["projects"] as? [[String: Any]],
              let first = list.first,
              let checkouts = first["checkouts"] as? [[String: Any]] else { return nil }
        return checkouts.first?["kind"] as? String
    }

    /// `projects` frame'indeki addable path'leri (Sendable [String] döner).
    func addablePaths() -> [String] {
        guard let payload = sent.first(where: { $0.type == "projects" })?.payload,
              let list = payload["addable"] as? [[String: String]] else { return [] }
        return list.compactMap { $0["path"] }
    }

    /// `projects` frame'indeki `others` grupları (path → agentIds).
    func otherGroups() -> [String: [String]] {
        guard let payload = sent.first(where: { $0.type == "projects" })?.payload,
              let list = payload["others"] as? [[String: Any]] else { return [:] }
        var groups: [String: [String]] = [:]
        for group in list {
            guard let path = group["path"] as? String else { continue }
            groups[path] = group["agentIds"] as? [String] ?? []
        }
        return groups
    }

    /// `projects` frame sayısı.
    func projectsCount() -> Int { sent.filter { $0.type == "projects" }.count }

    /// En son `projects` frame'indeki proje path'leri.
    func lastProjectPaths() -> [String] {
        guard let payload = sent.last(where: { $0.type == "projects" })?.payload,
              let list = payload["projects"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["path"] as? String }
    }
}

/// Sendable özet: `projects` frame'inin 2026-10-23 additive alanları.
struct ProjectsPayloadSnapshot: Sendable {
    let appearances: [String: [String: String]]
    let looseLocationPaths: [String]
    let fontFamily: String?
}

extension FakeRelayConnection {
    func lastProjectsPayloadSnapshot() -> ProjectsPayloadSnapshot? {
        guard let payload = sent.last(where: { $0.type == "projects" })?.payload,
              let list = payload["projects"] as? [[String: Any]] else { return nil }
        var appearances: [String: [String: String]] = [:]
        for project in list {
            if let path = project["path"] as? String, let appearance = project["appearance"] as? [String: String] {
                appearances[path] = appearance
            }
        }
        let locations = (payload["looseLocations"] as? [[String: String]] ?? []).compactMap { $0["path"] }
        let display = payload["display"] as? [String: String]
        return ProjectsPayloadSnapshot(
            appearances: appearances, looseLocationPaths: locations, fontFamily: display?["terminalFontFamily"])
    }
}

// MARK: - Tests

/// Task 8: Mac → phone projects broadcast.
/// Favorited repo'dan `projects` frame'inin welcome'da yayınlanması.
@Suite @MainActor struct RemoteServiceProjectsTests {

    // MARK: - T1: welcome → projects frame yayınlanır (favorited repo)

    /// Bir favorited repo + welcome → projects frame gönderilmeli;
    /// payload'da proje path'i + "original" checkout bulunmalı.
    @Test func welcomeBroadcastsProjectsFromFavorites() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let repos = FakeRepoService(repos: [
            Repo(name: "unco", path: "/p/unco", isGitRepo: true, source: .standalone)
        ])
        let cfg = FakeConfigService()
        await cfg.seed(AppConfig(
            projectsRoot: "",
            additionalPaths: [],
            aiProvider: .claude,
            theme: "dark",
            terminalFontSize: 13,
            terminalFontFamily: "",
            terminalCursorStyle: "block",
            terminalCursorBlink: true,
            notifications: .defaults,
            sidebarProjectPaths: ["/p/unco"]
        ))

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: repos,
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: cfg
        )
        await svc.start()

        // Act: phone sends welcome
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["projects"])

        // Assert: projects frame içeriği
        #expect(await conn.projectPaths() == ["/p/unco"])
        #expect(await conn.firstCheckoutKind() == "original")

        svc.stop()
    }

    // MARK: - Karar 108/114: Other

    /// Hiçbir checkout'a ait olmayan terminal `others`'ta dizinine göre gelir;
    /// checkout terminali orada görünmez.
    @Test func looseTerminalsArriveUnderOthers() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let base = Date(timeIntervalSince1970: 0)
        let inProject = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/p/unco", createdAt: base)
        let older = TerminalMeta(id: TerminalID(), name: "b", repoPath: "/tmp/scratch", createdAt: base)
        let newer = TerminalMeta(id: TerminalID(), name: "c", repoPath: "/tmp/scratch", createdAt: base.addingTimeInterval(9))
        term.metas = [inProject, older, newer]
        let repos = FakeRepoService(repos: [
            Repo(name: "unco", path: "/p/unco", isGitRepo: true, source: .standalone)
        ])
        let cfg = FakeConfigService()
        await cfg.seed(AppConfig(
            projectsRoot: "",
            additionalPaths: [],
            aiProvider: .claude,
            theme: "dark",
            terminalFontSize: 13,
            terminalFontFamily: "",
            terminalCursorStyle: "block",
            terminalCursorBlink: true,
            notifications: .defaults,
            sidebarProjectPaths: ["/p/unco"]
        ))

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: repos,
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: cfg
        )
        await svc.start()
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["projects"])

        #expect(await conn.otherGroups() == ["/tmp/scratch": [newer.id.description, older.id.description]])

        svc.stop()
    }

    // MARK: - 2026-10-23: görünüm, serbest konumlar, terminal fontu

    /// Projenin görünümü `appearance` altında, serbest konumlar (home + kökler)
    /// `looseLocations`'ta ve terminal fontu `display`'de gelir; görünümü boş
    /// projede `appearance` anahtarı yazılmaz.
    @Test func projectsCarryAppearanceLocationsAndFont() async throws {
        let conn = FakeRelayConnection()
        let repos = FakeRepoService(repos: [
            Repo(name: "game", path: "/p/game", isGitRepo: true, source: .standalone),
            Repo(name: "plain", path: "/p/plain", isGitRepo: true, source: .standalone),
        ])
        let cfg = FakeConfigService()
        await cfg.seed(AppConfig(
            projectsRoot: "",
            additionalPaths: [AdditionalPath(id: "src", path: "/src", type: .root)],
            aiProvider: .claude,
            theme: "dark",
            terminalFontSize: 13,
            terminalFontFamily: "Menlo",
            terminalCursorStyle: "block",
            terminalCursorBlink: true,
            notifications: .defaults,
            sidebarProjectPaths: ["/p/game", "/p/plain"],
            projectAppearance: ["/p/game": ProjectAppearance(
                color: .lime, icon: .emoji("🏖️"), rootTitle: "dev")]
        ))
        let svc = RemoteService(
            paths: .testDefaults(), terminal: FakeTerminalServicing(), repos: repos,
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: cfg
        )
        await svc.start()
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["projects"])

        let payload = try #require(await conn.lastProjectsPayloadSnapshot())
        #expect(payload.appearances == ["/p/game": ["color": "lime", "icon": "emoji:🏖️", "rootTitle": "dev"]])
        #expect(payload.looseLocationPaths == [NSHomeDirectory(), "/src"])
        #expect(payload.fontFamily == "Menlo")

        svc.stop()
    }

    /// Görünüm değişikliği (karar 120) telefona yeni `projects` yayınlar.
    @Test func appearanceChangeRebroadcastsProjects() {
        let base = AppConfig.defaults
        var colored = base
        colored.projectAppearance = ["/p/game": ProjectAppearance(color: .blue)]
        var font = base
        font.terminalFontFamily = "Menlo"
        #expect(RemoteService.projectsInputsChanged(base, colored))
        #expect(RemoteService.projectsInputsChanged(base, font))
        #expect(!RemoteService.projectsInputsChanged(base, base))
    }

    // MARK: - T2: addable = repos - favorited

    /// Favorited olmayan repo → addable'da görünmeli.
    @Test func nonFavoritedRepoAppearsInAddable() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let repos = FakeRepoService(repos: [
            Repo(name: "fav", path: "/p/fav", isGitRepo: true, source: .standalone),
            Repo(name: "other", path: "/p/other", isGitRepo: false, source: .standalone),
        ])
        let cfg = FakeConfigService()
        await cfg.seed(AppConfig(
            projectsRoot: "",
            additionalPaths: [],
            aiProvider: .claude,
            theme: "dark",
            terminalFontSize: 13,
            terminalFontFamily: "",
            terminalCursorStyle: "block",
            terminalCursorBlink: true,
            notifications: .defaults,
            sidebarProjectPaths: ["/p/fav"]
        ))

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: repos,
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: cfg
        )
        await svc.start()
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["projects"])

        let addable = await conn.addablePaths()
        #expect(addable.contains("/p/other"))
        #expect(!addable.contains("/p/fav"))

        svc.stop()
    }

    // MARK: - T4: config-change broadcast trigger

    /// Mac'te projeyi favoritelere eklemek → telefona projects frame yayını.
    /// `RemoteService.configTask`: `.configChanged` ile farklı `sidebarProjectPaths`
    /// gelince `sendProjects()` çağrılmalı — bu production yolu test-kilitleniyor.
    @Test func configChangeBroadcastsUpdatedProjects() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let repos = FakeRepoService(repos: [
            Repo(name: "unco", path: "/p/unco", isGitRepo: true, source: .standalone)
        ])
        let cfg = FakeConfigService()
        // Başlangıçta favorites boş → sidebarProjectPaths: []
        let emptyConfig = AppConfig(
            projectsRoot: "",
            additionalPaths: [],
            aiProvider: .claude,
            theme: "dark",
            terminalFontSize: 13,
            terminalFontFamily: "",
            terminalCursorStyle: "block",
            terminalCursorBlink: true,
            notifications: .defaults,
            sidebarProjectPaths: []
        )
        await cfg.seed(emptyConfig)

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: repos,
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: cfg
        )
        await svc.start()

        // Welcome → ilk projects frame (boş liste, count == 1)
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["projects"])
        let countAfterWelcome = await conn.projectsCount()

        // Config değişikliği: /p/unco favoritelere eklendi.
        // Önce stored config güncellenir (production'da disk yazımı önce olur),
        // sonra configChanged eventi yayınlanır.
        let newConfig = AppConfig(
            projectsRoot: "",
            additionalPaths: [],
            aiProvider: .claude,
            theme: "dark",
            terminalFontSize: 13,
            terminalFontFamily: "",
            terminalCursorStyle: "block",
            terminalCursorBlink: true,
            notifications: .defaults,
            sidebarProjectPaths: ["/p/unco"]
        )
        await cfg.seed(newConfig)
        cfg.emitConfigChange(old: emptyConfig, new: newConfig)

        // Config emit sonrası ikinci bir projects frame gelmeli
        try await conn.waitForCount(type: "projects", atLeast: countAfterWelcome + 1)

        // En son projects frame'i /p/unco içermeli
        let lastPaths = await conn.lastProjectPaths()
        #expect(lastPaths.contains("/p/unco"))

        svc.stop()
    }

    // MARK: - T3: boş favorites → projects: []

    /// Favorites boşken projects frame gönderilmeli, projects: [] olmalı.
    @Test func emptyFavoritesSendsEmptyProjectsList() async throws {
        let conn = FakeRelayConnection()
        let term = FakeTerminalServicing()
        let repos = FakeRepoService(repos: [
            Repo(name: "r", path: "/p/r", isGitRepo: true, source: .standalone)
        ])
        let cfg = FakeConfigService() // defaults → sidebarProjectPaths: []

        let svc = RemoteService(
            paths: .testDefaults(), terminal: term, repos: repos,
            connection: conn, chatSource: FakeChatTranscriptSource(events: []),
            hookEvents: { AsyncStream { _ in } }, config: cfg
        )
        await svc.start()
        await conn.injectInbound(type: "welcome", payload: [:])
        try await conn.waitForSent(types: ["projects"])

        #expect(await conn.projectPaths().isEmpty)

        svc.stop()
    }
}
