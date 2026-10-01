import XCTest

@testable import LumiKit

final class GitRefDisplayTests: XCTestCase {
    func testDropsRemoteTrackingRefSittingOnSameCommitAsLocalBranch() {
        let refs = [
            GitRef(name: "feature", kind: .localBranch),
            GitRef(name: "origin/feature", kind: .remoteBranch),
            GitRef(name: "origin/other", kind: .remoteBranch),
        ]

        XCTAssertEqual(GitRefDisplay.dedupeRemoteTracking(refs).map(\.name), ["feature", "origin/other"])
    }

    func testKeepsAmbiguousAndMultiRemoteMatches() {
        let refs = [
            GitRef(name: "main", kind: .localBranch),
            GitRef(name: "origin/main", kind: .remoteBranch),
            GitRef(name: "upstream/main", kind: .remoteBranch),
            GitRef(name: "foo/bar/main", kind: .remoteBranch),
        ]

        XCTAssertEqual(GitRefDisplay.dedupeRemoteTracking(refs), refs)
    }

    func testBadgesPutCurrentThenUpstreamFirst() {
        let refs = [
            GitRef(name: "v1.2.0", kind: .tag),
            GitRef(name: "origin/release", kind: .remoteBranch),
            GitRef(name: "main", kind: .localBranch, isCurrent: true),
        ]

        let badges = GitRefDisplay.badges(refs, upstream: "origin/release")

        XCTAssertEqual(badges.map(\.name), ["main", "origin/release", "v1.2.0"])
    }
}
