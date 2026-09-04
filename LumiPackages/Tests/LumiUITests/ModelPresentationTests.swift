import LumiKit
import XCTest
@testable import LumiUI

/// Model → UI string'lerinin LumiUI presenter extension'larına taşınması
/// (refactor 5.9): LumiKit modelleri artık sunum metni taşımaz.
final class ModelPresentationTests: XCTestCase {
    func testUsageLimitTitlesNormalizeKnownKinds() {
        let window = UsageWindow(percentUsed: 10, resetsAt: nil, resetsRaw: "", timezone: nil)
        func limit(_ kind: UsageLimit.Kind, raw: String = "raw label") -> UsageLimit {
            UsageLimit(kind: kind, rawLabel: raw, window: window)
        }

        XCTAssertEqual(limit(.session).displayTitle, "5-hour session")
        XCTAssertEqual(limit(.weeklyAll).displayTitle, "Weekly (all models)")
        XCTAssertEqual(limit(.weeklyModel("Opus")).displayTitle, "Weekly (Opus)")
        XCTAssertEqual(
            limit(.other, raw: "Current week (Fable)").displayTitle,
            "Current week (Fable)",
            "tanınmayan satır ham etiketini gösterir"
        )
    }

    func testFileChangeStatusBadges() {
        XCTAssertEqual(FileChangeStatus.modified.badgeText, "M")
        XCTAssertEqual(FileChangeStatus.added.badgeText, "A")
        XCTAssertEqual(FileChangeStatus.deleted.badgeText, "D")
        XCTAssertEqual(FileChangeStatus.renamed.badgeText, "R")
        XCTAssertEqual(FileChangeStatus.untracked.badgeText, "U")
    }

    func testCursorShapeLabels() {
        XCTAssertEqual(
            TerminalCursorShape.allCases.map(\.displayLabel),
            ["Block", "Underline", "Bar"]
        )
    }

    func testAgentProviderDisplayNamesAreCapitalizedForButtons() {
        XCTAssertEqual(AgentProvider.claude.displayName, "Claude")
        XCTAssertEqual(AgentProvider.codex.displayName, "Codex")
    }
}
