import Foundation
import LumiKit
import XCTest

@testable import LumiServices

/// Refactor 3.10: porcelain parse artık saf ve doğrudan test edilebilir
/// (eskiden yalnız gerçek-git entegrasyon testleriyle dolaylı kapsanıyordu).
final class GitPorcelainParserTests: XCTestCase {
    // MARK: - branch --list

    func testParsesBranchesAndMarksCurrent() {
        let raw = "  feature/x\n* main\n  release\n"

        let branches = GitPorcelainParser.parseBranches(raw)

        XCTAssertEqual(branches.map(\.name), ["feature/x", "main", "release"])
        XCTAssertEqual(branches.map(\.isCurrent), [false, true, false])
    }

    func testSkipsDetachedHeadLine() {
        let raw = "* (HEAD detached at abc1234)\n  main\n"

        XCTAssertEqual(GitPorcelainParser.parseBranches(raw).map(\.name), ["main"])
    }

    // MARK: - default branch

    func testDefaultBranchPrefersMainOverMaster() {
        XCTAssertEqual(GitPorcelainParser.defaultBranch(from: ["master", "main"]), "main")
        XCTAssertEqual(GitPorcelainParser.defaultBranch(from: ["master"]), "master")
        XCTAssertNil(GitPorcelainParser.defaultBranch(from: ["trunk"]))
    }

    func testDefaultBranchFromRefOutputTrimsWhitespace() {
        XCTAssertEqual(GitPorcelainParser.defaultBranch(fromRefOutput: " master \n"), "master")
        XCTAssertNil(GitPorcelainParser.defaultBranch(fromRefOutput: ""))
    }

    // MARK: - log

    func testParsesCommitRecordSeparatedByUnitSeparator() {
        let raw = "abc123\u{1f}abc\u{1f}Ada\u{1f}2026-09-04T10:00:00Z\u{1f}feat: bir şey"

        let commits = GitPorcelainParser.parseCommits(raw)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].hash, "abc123")
        XCTAssertEqual(commits[0].shortHash, "abc")
        XCTAssertEqual(commits[0].author, "Ada")
        XCTAssertEqual(commits[0].message, "feat: bir şey")
        XCTAssertEqual(
            commits[0].date,
            ISO8601DateFormatter().date(from: "2026-09-04T10:00:00Z")
        )
    }

    func testCommitMessageMayContainSeparatorLikeText() {
        // maxSplits=4: mesajda ayraç geçse bile mesaj bölünmez.
        let raw = "h\u{1f}s\u{1f}A\u{1f}2026-09-04T10:00:00Z\u{1f}a\u{1f}b"

        XCTAssertEqual(GitPorcelainParser.parseCommits(raw).first?.message, "a\u{1f}b")
    }

    func testUnparseableDateFallsBackToEpoch() {
        let raw = "h\u{1f}s\u{1f}A\u{1f}not-a-date\u{1f}msg"

        XCTAssertEqual(
            GitPorcelainParser.parseCommits(raw).first?.date,
            Date(timeIntervalSince1970: 0)
        )
    }

    func testDropsMalformedCommitLines() {
        XCTAssertTrue(GitPorcelainParser.parseCommits("bozuk satır").isEmpty)
    }

    // MARK: - status --porcelain

    func testStatusCollapsesIndexAndWorktreeCodes() {
        let raw = """
        ?? yeni.txt
         M değişen.txt
        A  eklenen.txt
         D silinen.txt
        MM ikisi.txt
        """

        let changes = GitPorcelainParser.parseStatus(raw)

        XCTAssertEqual(
            changes.map(\.path),
            ["yeni.txt", "değişen.txt", "eklenen.txt", "silinen.txt", "ikisi.txt"]
        )
        XCTAssertEqual(
            changes.map(\.status),
            [.untracked, .modified, .added, .deleted, .modified]
        )
    }

    func testRenameKeepsDestinationPath() {
        let change = GitPorcelainParser.parseStatusLine("R  eski.txt -> yeni.txt")

        XCTAssertEqual(change?.path, "yeni.txt")
        XCTAssertEqual(change?.status, .renamed)
    }

    func testQuotedPathIsUnescaped() {
        let change = GitPorcelainParser.parseStatusLine(#" M "boşluklu \"ad\".txt""#)

        XCTAssertEqual(change?.path, #"boşluklu "ad".txt"#)
    }

    func testTooShortStatusLineIsDropped() {
        XCTAssertNil(GitPorcelainParser.parseStatusLine(" M "))
    }

    func testZeroTerminatedStatusPreservesSpecialPathsAndConsumesRenameSource() {
        let raw = "?? quote\\\"é.txt\0R  new → name\0old\nname\0"
        let changes = GitPorcelainParser.parseStatusZeroTerminated(raw)
        XCTAssertEqual(changes.map(\.path), ["quote\\\"é.txt", "new → name"])
        XCTAssertEqual(changes.map(\.status), [.untracked, .renamed])
    }

    // MARK: - diff-tree --name-status

    func testDiffTreeNormalizesScoredStatuses() {
        let raw = """
        A\teklenen.swift
        D\tsilinen.swift
        R100\teski.swift\tyeni.swift
        C75\tkaynak.swift\tkopya.swift
        M\tdeğişen.swift
        """

        let files = GitPorcelainParser.parseDiffTree(raw)

        XCTAssertEqual(
            files.map(\.path),
            ["eklenen.swift", "silinen.swift", "yeni.swift", "kopya.swift", "değişen.swift"]
        )
        XCTAssertEqual(
            files.map(\.status),
            [.added, .deleted, .renamed, .renamed, .modified]
        )
    }

    func testDiffTreeDropsLinesWithoutTab() {
        XCTAssertTrue(GitPorcelainParser.parseDiffTree("Aeklenen.swift").isEmpty)
    }
}
