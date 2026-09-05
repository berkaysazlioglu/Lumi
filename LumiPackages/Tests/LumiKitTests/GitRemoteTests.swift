import Foundation
import XCTest

@testable import LumiKit

/// Remote URL normalizasyonu: ssh/https/scp biçimleri tek `owner/repo`ya iner,
/// GitHub dışı host'lar sessizce elenir.
final class GitRemoteTests: XCTestCase {
    func testNormalizesSCPStyleSSHRemote() {
        XCTAssertEqual(GitRemote.gitHubSlug(from: "git@github.com:owner/repo.git"), "owner/repo")
    }

    func testNormalizesSSHURLRemote() {
        XCTAssertEqual(
            GitRemote.gitHubSlug(from: "ssh://git@github.com/owner/repo.git"), "owner/repo"
        )
    }

    func testNormalizesHTTPSRemoteWithAndWithoutGitSuffix() {
        XCTAssertEqual(GitRemote.gitHubSlug(from: "https://github.com/owner/repo.git"), "owner/repo")
        XCTAssertEqual(GitRemote.gitHubSlug(from: "https://github.com/owner/repo"), "owner/repo")
    }

    func testTrimsSurroundingWhitespaceFromCommandOutput() {
        XCTAssertEqual(
            GitRemote.gitHubSlug(from: "  git@github.com:owner/repo.git\n"), "owner/repo"
        )
    }

    func testRejectsNonGitHubHosts() {
        XCTAssertNil(GitRemote.gitHubSlug(from: "git@gitlab.com:owner/repo.git"))
        XCTAssertNil(GitRemote.gitHubSlug(from: "https://bitbucket.org/owner/repo.git"))
        XCTAssertFalse(GitRemote.isGitHub("https://example.com/owner/repo.git"))
    }

    func testRejectsEmptyAndMalformedRemotes() {
        XCTAssertNil(GitRemote.gitHubSlug(from: ""))
        XCTAssertNil(GitRemote.gitHubSlug(from: "   "))
        XCTAssertNil(GitRemote.gitHubSlug(from: "https://github.com/owner"))
    }

    func testBuildsWebAndCommitURLs() {
        XCTAssertEqual(
            GitRemote.webURL(from: "git@github.com:owner/repo.git")?.absoluteString,
            "https://github.com/owner/repo"
        )
        XCTAssertEqual(
            GitRemote.commitURL(from: "https://github.com/owner/repo", sha: "abc123")?.absoluteString,
            "https://github.com/owner/repo/commit/abc123"
        )
    }

    func testCommitURLRequiresSHA() {
        XCTAssertNil(GitRemote.commitURL(from: "git@github.com:owner/repo.git", sha: "  "))
    }
}
