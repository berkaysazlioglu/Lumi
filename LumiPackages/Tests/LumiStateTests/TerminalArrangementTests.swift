import Foundation
import LumiKit
import XCTest
@testable import LumiState

/// Karar 103: All Terminals'ın kendi kart sırası — saf değer tipi.
final class TerminalArrangementTests: XCTestCase {
    private func meta(
        _ name: String,
        repo: String = "/r/alpha",
        claude: String? = nil,
        codex: String? = nil
    ) -> TerminalMeta {
        TerminalMeta(
            id: TerminalID(), name: name, repoPath: repo, createdAt: Date(),
            claudeSessionID: claude, codexSessionID: codex,
            provider: codex == nil ? (claude == nil ? nil : .claude) : .codex
        )
    }

    private func names(_ metas: [TerminalMeta]) -> [String] {
        metas.map(\.name)
    }

    // MARK: - Sıralama

    func testEmptyArrangementKeepsIncomingOrder() {
        let metas = [meta("a"), meta("b", repo: "/r/beta"), meta("c")]
        XCTAssertEqual(names(TerminalArrangement().ordered(metas)), ["a", "b", "c"])
    }

    func testSwapCrossesRepoBoundariesWithoutTouchingOthers() {
        let a = meta("a"), b = meta("b", repo: "/r/beta"), c = meta("c")
        var arrangement = TerminalArrangement()

        XCTAssertTrue(arrangement.swap(a.id, c.id, among: [a, b, c]))

        XCTAssertEqual(names(arrangement.ordered([a, b, c])), ["c", "b", "a"])
    }

    func testSwapWithUnknownOrSameTerminalIsRefused() {
        let a = meta("a"), b = meta("b")
        var arrangement = TerminalArrangement()
        XCTAssertFalse(arrangement.swap(a.id, a.id, among: [a, b]))
        XCTAssertFalse(arrangement.swap(a.id, TerminalID(), among: [a, b]))
        XCTAssertEqual(names(arrangement.ordered([a, b])), ["a", "b"])
    }

    func testNewTerminalsAppendAfterArrangedOnes() {
        let a = meta("a"), b = meta("b")
        var arrangement = TerminalArrangement()
        arrangement.swap(a.id, b.id, among: [a, b])

        let c = meta("c")
        XCTAssertEqual(names(arrangement.ordered([a, b, c])), ["b", "a", "c"])
    }

    func testPinDropsExitedTerminals() {
        let a = meta("a"), b = meta("b"), c = meta("c")
        var arrangement = TerminalArrangement()
        arrangement.swap(a.id, c.id, among: [a, b, c])

        arrangement.pin([b, c])

        XCTAssertEqual(arrangement.entries, [.terminal(c.id), .terminal(b.id)])
    }

    // MARK: - Açılışta geri kurma

    /// Resume spawn'ları resume listesi sırasıyla gelir; All Terminals sırası
    /// ise ayrıdır — doğan oturum kendi eski yerine oturmalı.
    func testRestoredKeysPlaceResumedTerminalsRegardlessOfSpawnOrder() {
        var arrangement = TerminalArrangement(restoring: ["s-2", "s-1"])
        let first = meta("first", claude: "s-1")
        arrangement.pin([first])
        let second = meta("second", repo: "/r/beta", claude: "s-2")
        arrangement.pin([first, second])

        XCTAssertEqual(names(arrangement.ordered([first, second])), ["second", "first"])
    }

    func testCodexTerminalsAreKeyedByTheirThreadID() {
        let arrangement = TerminalArrangement(restoring: ["thread-b", "s-a"])
        let claude = meta("claude", claude: "s-a")
        // Codex'te Claude alanı da dolu olsa resume kimliği thread kimliğidir.
        let codex = meta("codex", claude: "ignored", codex: "thread-b")

        XCTAssertEqual(names(arrangement.ordered([claude, codex])), ["codex", "claude"])
    }

    /// Karar 94: `/clear` oturum kimliğini değiştirir — sabitlenmiş terminal
    /// yerini korumalı.
    func testPinnedTerminalKeepsItsPlaceAfterSessionIDChanges() {
        var arrangement = TerminalArrangement(restoring: ["s-2", "s-1"])
        var first = meta("first", claude: "s-1")
        let second = meta("second", claude: "s-2")
        arrangement.pin([first, second])

        first.claudeSessionID = "s-1-cleared"
        arrangement.pin([first, second])

        XCTAssertEqual(names(arrangement.ordered([first, second])), ["second", "first"])
    }

    func testUnbornResumeEntriesWaitInPlace() {
        var arrangement = TerminalArrangement(restoring: ["s-1", "s-2", "s-3"])
        let third = meta("third", claude: "s-3")
        arrangement.pin([third])

        XCTAssertEqual(arrangement.entries, [.resumed("s-1"), .resumed("s-2"), .terminal(third.id)])
    }

    func testDuplicateSessionIDPlacesOnlyTheFirstTerminal() {
        let arrangement = TerminalArrangement(restoring: ["s-1"])
        let fresh = meta("fresh")
        let original = meta("original", claude: "s-1")
        let duplicate = meta("duplicate", claude: "s-1")

        XCTAssertEqual(
            names(arrangement.ordered([fresh, original, duplicate])),
            ["original", "fresh", "duplicate"]
        )
    }

    func testRestoringIgnoresDuplicateKeys() {
        XCTAssertEqual(TerminalArrangement(restoring: ["s-1", "s-1"]).entries, [.resumed("s-1")])
    }

    // MARK: - Diske inen sıra

    func testPersistedKeysAreLiveResumableSessionsInDisplayOrder() {
        var arrangement = TerminalArrangement(restoring: ["gone"])
        let shell = meta("shell")
        let claude = meta("claude", claude: "s-1")
        let codex = meta("codex", codex: "thread-1")
        arrangement.swap(claude.id, codex.id, among: [shell, claude, codex])

        XCTAssertEqual(arrangement.persistedKeys([shell, claude, codex]), ["thread-1", "s-1"])
    }
}
