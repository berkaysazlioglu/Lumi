import Foundation
import Testing
@testable import LumiKit

/// Karar 120: proje rengi — sahiplik çözümü ve kart kenarlığının önceliği.
@Suite struct ProjectColorTests {
    /// `NavigationStore.projectPath(containing:)` yerine geçen sahte sahiplik:
    /// proje kökü kendisine, workspace/worktree projesine aittir, serbest yol
    /// hiçbir projeye ait değildir.
    private let owners: [String: String] = [
        "/p/game": "/p/game",
        "/w/game-feature": "/p/game",
        "/p/game-wt": "/p/game",
        "/p/tool": "/p/tool",
    ]
    private func owner(_ path: String) -> String? { owners[path] }

    @Test func checkoutsTakeTheirProjectsColor() {
        let colors: [String: ProjectColor] = ["/p/game": .teal]
        #expect(ProjectColorResolver.color(forCheckout: "/p/game", colors: colors, owningProject: owner) == .teal)
        #expect(ProjectColorResolver.color(forCheckout: "/w/game-feature", colors: colors, owningProject: owner) == .teal)
        #expect(ProjectColorResolver.color(forCheckout: "/p/game-wt", colors: colors, owningProject: owner) == .teal)
    }

    @Test func uncoloredProjectAndLooseTerminalHaveNoColor() {
        let colors: [String: ProjectColor] = ["/p/game": .teal, "/Users/me": .pink]
        #expect(ProjectColorResolver.color(forCheckout: "/p/tool", colors: colors, owningProject: owner) == nil)
        // Serbest yol renk sözlüğünde anahtar olarak dursa bile renk almaz —
        // sahiplik önce gelir (karar 108).
        #expect(ProjectColorResolver.color(forCheckout: "/Users/me", colors: colors, owningProject: owner) == nil)
    }

    @Test func noColorsMeansOwnershipIsNeverAsked() {
        var asked = 0
        let lookup: (String) -> String? = { asked += 1; return $0 }
        let meta = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/p/game", createdAt: Date())
        #expect(ProjectColorResolver.colors(for: [meta], colors: [:], owningProject: lookup).isEmpty)
        #expect(asked == 0)
    }

    @Test func terminalMapSkipsUncoloredAndAsksOncePerCheckout() {
        var asked: [String] = []
        let lookup: (String) -> String? = { asked.append($0); return owners[$0] }
        let root = TerminalMeta(id: TerminalID(), name: "a", repoPath: "/p/game", createdAt: Date())
        let rootTwo = TerminalMeta(id: TerminalID(), name: "b", repoPath: "/p/game", createdAt: Date())
        let workspace = TerminalMeta(id: TerminalID(), name: "c", repoPath: "/w/game-feature", createdAt: Date())
        let tool = TerminalMeta(id: TerminalID(), name: "d", repoPath: "/p/tool", createdAt: Date())
        let loose = TerminalMeta(id: TerminalID(), name: "e", repoPath: "/Users/me", createdAt: Date())

        let map = ProjectColorResolver.colors(
            for: [root, rootTwo, workspace, tool, loose],
            colors: ["/p/game": .orange],
            owningProject: lookup
        )

        #expect(map == [root.id: .orange, rootTwo.id: .orange, workspace.id: .orange])
        #expect(asked == ["/p/game", "/w/game-feature", "/p/tool", "/Users/me"])
    }

    // MARK: - Kenarlık önceliği: seçili (proje rengi | accent) > dikkat > proje rengi soluk > border

    @Test func activeBeatsEverythingAndKeepsTheProjectsColor() {
        #expect(TerminalBorderEmphasis.resolve(isActive: true, needsAttention: true, projectColor: .blue) == .active(.blue))
        #expect(TerminalBorderEmphasis.resolve(isActive: true, needsAttention: false, projectColor: .lime) == .active(.lime))
        #expect(
            TerminalBorderEmphasis.resolve(isActive: true, needsAttention: false, projectColor: nil) == .active(nil),
            "renksiz proje bugünkü accent ring'ini korur"
        )
    }

    @Test func attentionBeatsProjectColor() {
        #expect(TerminalBorderEmphasis.resolve(isActive: false, needsAttention: true, projectColor: .lime) == .attention)
    }

    @Test func projectColorReplacesTheRestingBorder() {
        #expect(TerminalBorderEmphasis.resolve(isActive: false, needsAttention: false, projectColor: .pink) == .project(.pink))
        #expect(TerminalBorderEmphasis.resolve(isActive: false, needsAttention: false, projectColor: nil) == .rest)
    }
}

/// Karar 120: görünüm modelinin doğrulama kuralları (codec ve store ortak).
@Suite struct ProjectAppearanceModelTests {
    @Test func emojiMustBeExactlyOneDisplayedEmojiGrapheme() {
        #expect(ProjectIcon.emoji(from: "🚀") == .emoji("🚀"))
        #expect(ProjectIcon.emoji(from: " 👍🏽 ") == .emoji("👍🏽"), "ten rengi değiştiricili tek grapheme")
        #expect(ProjectIcon.emoji(from: "👨‍👩‍👧") == .emoji("👨‍👩‍👧"), "ZWJ dizisi tek grapheme")
        #expect(ProjectIcon.emoji(from: "❤️") == .emoji("❤️"), "VS16 ile emoji sunumu")
        #expect(ProjectIcon.emoji(from: "🚀🚀") == nil)
        #expect(ProjectIcon.emoji(from: "a") == nil)
        #expect(ProjectIcon.emoji(from: "1") == nil, "emoji özelliği var ama metin olarak çizilir")
        #expect(ProjectIcon.emoji(from: "") == nil)
    }

    @Test func symbolsComeOnlyFromTheAllowlist() {
        #expect(ProjectIcon.symbol(named: "star") == .symbol("star"))
        #expect(ProjectIcon.symbol(named: "trash") == nil)
        #expect(ProjectIcon.symbolNames.first == "folder")
        #expect(Set(ProjectIcon.symbolNames).count == ProjectIcon.symbolNames.count)
        #expect(ProjectIcon(persisted: "sf:trash") == nil)
        #expect(ProjectIcon(persisted: "emoji:🚀") == .emoji("🚀"))
        #expect(ProjectIcon(persisted: "🚀") == nil)
    }

    @Test func titleIsTrimmedLimitedAndDefaultsToMain() {
        #expect(ProjectRootTitle.normalized("  dev  ") == "dev")
        #expect(ProjectRootTitle.normalized("   ") == nil)
        #expect(ProjectRootTitle.normalized("main") == nil, "varsayılan diske yazılmaz")
        #expect(ProjectRootTitle.normalized(String(repeating: "x", count: 40))?.count == ProjectRootTitle.maxLength)
        #expect(ProjectAppearance(rootTitle: " ").resolvedRootTitle == "main")
    }

    @Test func defaultIconIsNotStoredAndEmptyAppearanceIsEmpty() {
        #expect(ProjectAppearance(icon: .default).icon == nil)
        #expect(ProjectAppearance(icon: .default, rootTitle: "main").isEmpty)
        #expect(ProjectAppearance.none.resolvedIcon == .symbol("folder"))
        #expect(!ProjectAppearance(color: .blue).isEmpty)
    }

    @Test func configExposesColorsOfColoredProjectsOnly() {
        var config = AppConfig.defaults
        config.projectAppearance = [
            "/p/a": ProjectAppearance(color: .teal),
            "/p/b": ProjectAppearance(rootTitle: "dev"),
        ]
        #expect(config.projectColors == ["/p/a": .teal])
        #expect(config.appearance(ofProject: "/p/missing") == .none)
    }
}
