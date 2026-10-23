import CoreGraphics

/// How far the chat's content end sits below the viewport's bottom edge.
///
/// `sentinelMinY` is the bottom sentinel's `minY` in the ScrollView's named
/// coordinate space and `viewportHeight` the ScrollView's own height: ≤ 0 when
/// pinned to the bottom (the list's bottom padding), growing as the user scrolls up.
/// `nil` means the sentinel is not realized: the lazy list unloads it once the user
/// scrolls far enough up, so a missing sentinel is "far" (decision 131).
public func chatDistanceFromBottom(sentinelMinY: CGFloat?, viewportHeight: CGFloat) -> CGFloat {
    guard let sentinelMinY else { return .infinity }
    return sentinelMinY - viewportHeight
}

/// Decision 131 (Claude Code auto-follow): while following, the chat stays on the
/// latest output as it grows; scrolling up pauses it and the jump button appears.
public struct ChatFollowPolicy: Sendable, Equatable {
    /// Distance the user may drift from the bottom and still follow — the jump
    /// button stays hidden inside it (2–3 lines).
    public let threshold: CGFloat
    /// Slack under which a following chat counts as already at the bottom.
    public static let pinnedSlack: CGFloat = 2
    /// Scrolled this far up the prompt header may show — before the jump button.
    public static let headerSlack: CGFloat = 4

    public init(threshold: CGFloat) {
        self.threshold = threshold
    }

    public struct Step: Sendable, Equatable {
        public let isFollowing: Bool
        /// Content moved without the user (it grew, the keyboard opened): re-pin.
        public let shouldScrollToBottom: Bool
        /// Off the bottom by the user's hand (or a jump up): the prompt header may show.
        public let isScrolledUp: Bool
    }

    /// One distance update. Only the user's own scrolling (finger down or momentum)
    /// changes whether the chat follows; anything else while following is content
    /// or layout moving underneath, so the chat re-pins to the bottom.
    public func step(distance: CGFloat, isFollowing: Bool, isUserScrolling: Bool) -> Step {
        let scrolledUp = distance > Self.headerSlack
        if isUserScrolling {
            return Step(isFollowing: distance <= threshold, shouldScrollToBottom: false, isScrolledUp: scrolledUp)
        }
        if isFollowing {
            // Growth is about to be re-pinned — no header flash.
            return Step(isFollowing: true, shouldScrollToBottom: distance > Self.pinnedSlack, isScrolledUp: false)
        }
        return Step(isFollowing: false, shouldScrollToBottom: false, isScrolledUp: scrolledUp)
    }

    /// The jump button: paused and outside the threshold.
    public func showsJumpButton(distance: CGFloat, isFollowing: Bool) -> Bool {
        !isFollowing && distance > threshold
    }
}
