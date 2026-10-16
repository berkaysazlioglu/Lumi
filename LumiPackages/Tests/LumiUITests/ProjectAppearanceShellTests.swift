import Foundation
import LumiKit
import LumiState
import LumiTestSupport
import XCTest
@testable import LumiUI

/// Karar 120: terminal → sahip proje → renk, kabuğun gerçek sahiplik
/// köprüsüyle (`NavigationStore.projectPath(containing:)`), palet tokenları,
/// proje menüsü ve kök checkout'un başlığı/ikonu.
@MainActor
final class ProjectAppearanceShellTests: XCTestCase {
    private var fixture: ShellContextFixture!
    private var shell: ShellContext { fixture.context }

    override func setUp() async throws {
        let repos = FakeRepoService()
        await repos.setRepos([
            Repo(name: "Game", path: "/projects/game", isGitRepo: true, source: .projectsRoot),
            Repo(name: "Tool", path: "/projects/tool", isGitRepo: true, source: .projectsRoot),
        ])
        fixture = await ShellContextFixture.make(repo: repos)
        await shell.repos.reload()
        shell.workspaces.updateSidebarProjects(["/projects/game", "/projects/tool"])
        shell.workspaces.updateRecords([
            ProjectWorkspace(projectPath: "/projects/game", path: "/lumi/workspaces/game-feature", name: "feature", branch: "feature", scm: .git),
            ProjectWorkspace(projectPath: "/projects/game", path: "/elsewhere/game-wt", name: "game-wt", branch: "wt", scm: .git),
        ])
        // `RepoFeatureAssembly.wireProjectNavigation` ile aynı köprü.
        let workspaces = shell.workspaces
        shell.navigation.projectOrder = { workspaces.addedProjects.map(\.path) }
        shell.navigation.projectCheckouts = { [$0] + workspaces.workspaces(for: $0).map(\.path) }
    }

    override func tearDown() async throws {
        fixture?.stop()
        fixture = nil
    }

    func testNoColorsMeansTodaysLook() async throws {
        try await fixture.spawnTerminal(in: "/projects/game")
        XCTAssertNil(shell.projectColor(forCheckout: "/projects/game"))
        XCTAssertTrue(shell.terminalProjectColors.isEmpty)
    }

    func testProjectRootWorkspaceAndWorktreeShareTheColorLooseDoesNot() async throws {
        shell.settings.setProjectColor(.teal, for: "/projects/game")

        let root = try await fixture.spawnTerminal(named: "root", in: "/projects/game")
        let workspace = try await fixture.spawnTerminal(named: "ws", in: "/lumi/workspaces/game-feature")
        let worktree = try await fixture.spawnTerminal(named: "wt", in: "/elsewhere/game-wt")
        let tool = try await fixture.spawnTerminal(named: "tool", in: "/projects/tool")
        let loose = try await fixture.spawnTerminal(named: "loose", in: "/Users/me/Desktop")

        XCTAssertEqual(shell.projectColor(forCheckout: "/lumi/workspaces/game-feature"), .teal)
        XCTAssertEqual(shell.terminalProjectColors, [root.id: .teal, workspace.id: .teal, worktree.id: .teal])
        XCTAssertNil(shell.terminalProjectColors[tool.id], "rengi olmayan proje")
        XCTAssertNil(shell.terminalProjectColors[loose.id], "karar 108: serbest terminal renksizdir")

        shell.settings.setProjectColor(nil, for: "/projects/game")
        XCTAssertTrue(shell.terminalProjectColors.isEmpty, "None bugünkü görünüme döner")
    }

    /// Proje Projects'ten kalkınca renk silinmez (favoriler gibi) ama artık
    /// sahibi olmayan terminaller renk almaz.
    func testRemovedProjectKeepsItsColorButStopsColoring() async throws {
        shell.settings.setProjectColor(.pink, for: "/projects/tool")
        let tool = try await fixture.spawnTerminal(in: "/projects/tool")
        XCTAssertEqual(shell.terminalProjectColors[tool.id], .pink)

        shell.workspaces.updateSidebarProjects(["/projects/game"])

        XCTAssertNil(shell.terminalProjectColors[tool.id])
        XCTAssertEqual(shell.settings.current.projectColors["/projects/tool"], .pink)
    }

    // MARK: - Palet

    func testPaletteIsDistinctFromStatusChannelsAndReadableOnDarkSurfaces() {
        let hexes = ProjectColor.allCases.map(Theme.ProjectTint.hex)
        XCTAssertEqual(Set(hexes).count, ProjectColor.allCases.count)
        for hex in hexes {
            XCTAssertFalse([Theme.Hex.warning, Theme.Hex.error, 0xA78BFA].contains(hex))
            XCTAssertGreaterThanOrEqual(contrast(hex, 0x12121F), 4.5, String(format: "%06X on bgSurface", hex))
            XCTAssertGreaterThanOrEqual(contrast(hex, 0x1A1A2E), 4.5, String(format: "%06X on bgElevated", hex))
        }
    }

    // MARK: - Menü + kök checkout

    func testProjectMenuOffersAppearanceInsteadOfAColorSubmenu() throws {
        let project = try XCTUnwrap(shell.repos.repo(at: "/projects/tool"))
        let items = ProjectsPanel.projectMenuItems(project, shell: shell, isOperationRunning: false)
        let titles: [String] = items.compactMap {
            switch $0 {
            case .action(let title, _, _, _, _), .submenu(let title, _, _, _): return title
            default: return nil
            }
        }
        XCTAssertEqual(titles, ["Create Workspace…", "Appearance…", "Reveal in Finder", "Copy Path", "Remove from Projects"])

        for case .action("Appearance…", _, _, _, let action) in items { action() }
        XCTAssertEqual(
            shell.dialogs.projectAppearanceDialog?.projectPath, "/projects/tool",
            "modal sağ tıklanan projeyle açılır"
        )
    }

    func testMainCheckoutTakesTheProjectsTitleAndIcon() throws {
        let game = try XCTUnwrap(shell.repos.repo(at: "/projects/game"))
        XCTAssertEqual(Checkout.original(game).identity(in: shell).title, "main")
        XCTAssertEqual(shell.settings.current.appearance(ofProject: game.path).resolvedIcon, .default)

        shell.settings.setProjectRootTitle("dev", for: game.path)
        shell.settings.setProjectIcon(.emoji("🎮"), for: game.path)

        XCTAssertEqual(Checkout.original(game).identity(in: shell).title, "dev")
        XCTAssertEqual(shell.settings.current.appearance(ofProject: game.path).resolvedIcon, .emoji("🎮"))
        XCTAssertEqual(shell.checkoutLabel(for: game.path), "Game", "All Terminals etiketi proje adıdır, main değil")
        XCTAssertEqual(ProjectTree.originalTitle, "main", "telefon/orchestrator ağacı değişmez")
    }

    /// Renkli kartın header tonları (karar 120): başlık iki hâlde de header
    /// zemini ve chip zemini üstünde ≥ 4,5:1, ikon butonları ≥ 3:1 (UI bileşeni).
    func testTintedHeaderTonesStayReadable() {
        typealias Tint = Theme.ProjectTint
        for color in ProjectColor.allCases {
            let hex = Tint.hex(color)
            let header = blend(Theme.Hex.bgElevated, hex, Tint.headerOpacity)
            let restTitle = blend(Theme.Hex.textSecondary, hex, Tint.restTitleBlend)
            let activeTitle = blend(Theme.Hex.textPrimary, hex, Tint.activeTitleBlend)
            let iconRest = blend(header, hex, Tint.iconRestOpacity)
            let name = color.rawValue
            XCTAssertGreaterThanOrEqual(contrast(restTitle, header), 4.5, "\(name) pasif başlık")
            XCTAssertGreaterThanOrEqual(contrast(activeTitle, header), 4.5, "\(name) seçili başlık")
            XCTAssertGreaterThanOrEqual(contrast(restTitle, Theme.Hex.bgSurface), 4.5, "\(name) chip başlığı")
            XCTAssertGreaterThanOrEqual(contrast(hex, header), 4.5, "\(name) checkout etiketi / hover ikon")
            XCTAssertGreaterThanOrEqual(contrast(iconRest, header), 3.0, "\(name) ikon butonu")
            XCTAssertGreaterThan(contrast(activeTitle, header), contrast(restTitle, header), "\(name) seçili daha parlak")
        }
    }

    /// `Theme.blend` ile aynı sRGB doğrusal ara ton (yuvarlanmış kanal).
    private func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let from = Double((a >> shift) & 0xFF)
            let to = Double((b >> shift) & 0xFF)
            return UInt32((from + (to - from) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// WCAG 2 göreli parlaklık kontrastı.
    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ shift: UInt32) -> Double {
                let c = Double((hex >> shift) & 0xFF) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
