import Testing
import LumiWire

@Suite("ProjectOrder / ProjectIdentityRules")
struct ProjectIdentityRulesTests {

    // MARK: - moving

    @Test func movingDownLandsBelowTarget() {
        #expect(ProjectOrder.moving("a", onto: "c", in: ["a", "b", "c"]) == ["b", "c", "a"])
    }

    @Test func movingUpLandsAboveTarget() {
        #expect(ProjectOrder.moving("c", onto: "a", in: ["a", "b", "c"]) == ["c", "a", "b"])
    }

    @Test func movingOntoItselfOrUnknownKeepsOrder() {
        #expect(ProjectOrder.moving("b", onto: "b", in: ["a", "b"]) == ["a", "b"])
        #expect(ProjectOrder.moving("x", onto: "a", in: ["a", "b"]) == ["a", "b"])
        #expect(ProjectOrder.moving("a", onto: "x", in: ["a", "b"]) == ["a", "b"])
    }

    // MARK: - applying

    @Test func applyingReordersVisibleSlotsAndKeepsHiddenInPlace() {
        // "h" is a favorite the phone never sees (e.g. a missing repo).
        let current = ["a", "h", "b", "c"]
        #expect(ProjectOrder.applying(["c", "a", "b"], to: current) == ["c", "h", "a", "b"])
    }

    @Test func applyingIgnoresUnknownAndDuplicatePaths() {
        #expect(ProjectOrder.applying(["b", "x", "b", "a"], to: ["a", "b"]) == ["b", "a"])
    }

    @Test func applyingPartialOrderOnlyPermutesNamedPaths() {
        #expect(ProjectOrder.applying(["c", "a"], to: ["a", "b", "c"]) == ["c", "b", "a"])
    }

    // MARK: - rules

    @Test func emojiValidation() {
        #expect(ProjectIdentityRules.emoji(from: " 🚀 ") == "🚀")
        #expect(ProjectIdentityRules.emoji(from: "🚀🚀") == nil)
        #expect(ProjectIdentityRules.emoji(from: "1") == nil)
        #expect(ProjectIdentityRules.emoji(from: "a") == nil)
    }

    @Test func rootTitleNormalization() {
        #expect(ProjectIdentityRules.normalizedRootTitle("  dev ") == "dev")
        #expect(ProjectIdentityRules.normalizedRootTitle("main") == nil)
        #expect(ProjectIdentityRules.normalizedRootTitle("   ") == nil)
        let long = String(repeating: "x", count: ProjectIdentityRules.rootTitleMaxLength + 5)
        #expect(ProjectIdentityRules.normalizedRootTitle(long)?.count == ProjectIdentityRules.rootTitleMaxLength)
    }
}
