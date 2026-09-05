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

    // MARK: - log -z --decorate=full (graph history, karar 40)

    private func record(
        hash: String,
        short: String,
        author: String = "Ada",
        date: String = "2026-01-02T03:04:05+03:00",
        parents: String = "",
        decoration: String = "",
        subject: String = "subject"
    ) -> String {
        [hash, short, author, date, parents, decoration, subject]
            .joined(separator: "\u{1f}")
    }

    func testParsesHistoryRecordsSeparatedByNUL() {
        let raw = [
            record(hash: "aaa", short: "aaa1111", parents: "bbb", subject: "second"),
            record(hash: "bbb", short: "bbb2222", subject: "first"),
        ].joined(separator: "\0")

        let commits = GitPorcelainParser.parseHistory(raw)

        XCTAssertEqual(commits.map(\.hash), ["aaa", "bbb"])
        XCTAssertEqual(commits.map(\.message), ["second", "first"])
        XCTAssertEqual(commits[0].parentHashes, ["bbb"])
        XCTAssertTrue(commits[1].parentHashes.isEmpty, "root commit'in parent'ı yok")
    }

    func testParsesMergeParentsInOrder() {
        let raw = record(hash: "mmm", short: "mmm1111", parents: "aaa bbb")

        let commits = GitPorcelainParser.parseHistory(raw)

        XCTAssertEqual(commits[0].parentHashes, ["aaa", "bbb"])
        XCTAssertTrue(commits[0].isMerge)
    }

    func testParsesFullDecorationIntoTypedRefs() {
        let raw = record(
            hash: "aaa", short: "aaa1111",
            decoration: "HEAD -> refs/heads/main, refs/remotes/origin/main, "
                + "refs/remotes/origin/HEAD, tag: refs/tags/v1.0"
        )

        let refs = GitPorcelainParser.parseHistory(raw)[0].references

        XCTAssertEqual(refs.map(\.name), ["main", "origin/main", "v1.0"])
        XCTAssertEqual(refs.map(\.kind), [.localBranch, .remoteBranch, .tag])
        XCTAssertEqual(refs.map(\.isCurrent), [true, false, false])
    }

    func testParsesShortDecorationForm() {
        let raw = record(hash: "aaa", short: "aaa1111", decoration: "HEAD -> main, origin/main, tag: v1.0")

        let refs = GitPorcelainParser.parseHistory(raw)[0].references

        XCTAssertEqual(refs.map(\.name), ["main", "origin/main", "v1.0"])
        XCTAssertEqual(refs.map(\.kind), [.localBranch, .remoteBranch, .tag])
    }

    func testMarksDetachedHeadAsHeadRef() {
        let refs = GitPorcelainParser.parseRefs("HEAD, refs/tags/v2")

        XCTAssertEqual(refs.map(\.kind), [.head, .tag])
        XCTAssertTrue(refs[0].isCurrent)
    }

    func testSortsRefsCurrentThenLocalThenRemoteThenTag() {
        let refs = GitPorcelainParser.parseRefs(
            "tag: refs/tags/v9, refs/remotes/origin/dev, refs/heads/dev, HEAD -> refs/heads/main"
        )

        XCTAssertEqual(refs.map(\.name), ["main", "dev", "origin/dev", "v9"])
    }

    func testSkipsMalformedHistoryRecords() {
        let raw = ["", "not-enough\u{1f}fields", record(hash: "aaa", short: "aaa1111")]
            .joined(separator: "\0")

        XCTAssertEqual(GitPorcelainParser.parseHistory(raw).map(\.hash), ["aaa"])
    }

    func testParsesEmptyDecorationAsNoRefs() {
        let commits = GitPorcelainParser.parseHistory(record(hash: "aaa", short: "aaa1111"))

        XCTAssertTrue(commits[0].references.isEmpty)
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
