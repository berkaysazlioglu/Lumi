import XCTest
@testable import LumiMobileKit

/// Decision 131: distance from the bottom + Claude Code-style auto-follow.
final class ChatScrollGateTests: XCTestCase {
    private let policy = ChatFollowPolicy(threshold: 48)

    func testDistanceFromBottom() {
        XCTAssertEqual(chatDistanceFromBottom(sentinelMinY: 592, viewportHeight: 600), -8)
        XCTAssertEqual(chatDistanceFromBottom(sentinelMinY: 700, viewportHeight: 600), 100)
    }

    func testUnloadedSentinelIsFar() {
        // The lazy list drops the sentinel far from the bottom.
        XCTAssertEqual(chatDistanceFromBottom(sentinelMinY: nil, viewportHeight: 600), .infinity)
    }

    func testUserScrollingWithinThresholdKeepsFollowing() {
        let step = policy.step(distance: 40, isFollowing: true, isUserScrolling: true)
        XCTAssertTrue(step.isFollowing)
        XCTAssertFalse(step.shouldScrollToBottom, "never fight the user's finger")
        XCTAssertFalse(policy.showsJumpButton(distance: 40, isFollowing: step.isFollowing))
        XCTAssertTrue(step.isScrolledUp, "the prompt header may show before the jump button")
    }

    func testUserScrollingPastThresholdPausesFollowing() {
        let step = policy.step(distance: 49, isFollowing: true, isUserScrolling: true)
        XCTAssertFalse(step.isFollowing)
        XCTAssertTrue(policy.showsJumpButton(distance: 49, isFollowing: step.isFollowing))
    }

    func testUserScrollingBackDownResumesFollowing() {
        XCTAssertTrue(policy.step(distance: 0, isFollowing: false, isUserScrolling: true).isFollowing)
    }

    func testContentGrowthWhileFollowingRepins() {
        let step = policy.step(distance: 300, isFollowing: true, isUserScrolling: false)
        XCTAssertTrue(step.isFollowing)
        XCTAssertTrue(step.shouldScrollToBottom)
        XCTAssertFalse(step.isScrolledUp, "no header flash while re-pinning")
        XCTAssertFalse(policy.step(distance: -8, isFollowing: true, isUserScrolling: false).shouldScrollToBottom,
                       "already pinned")
    }

    func testContentGrowthWhilePausedStaysPut() {
        // Also a jump to a prompt: programmatic, paused — must not snap back down.
        let step = policy.step(distance: 300, isFollowing: false, isUserScrolling: false)
        XCTAssertFalse(step.isFollowing)
        XCTAssertFalse(step.shouldScrollToBottom)
    }
}
