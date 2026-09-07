import Foundation
import XCTest
@testable import LumiKit

/// `RelativeTimeFormatter.label` — commit timeline'ının SAF "Xm/Xh/Xd ago"
/// biçimlendirmesi (refactor plan 2.8). `now` enjekte edildiği için
/// deterministik (duvar saatine bağlı değil).
@MainActor
final class RelativeTimeFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func label(secondsAgo: TimeInterval) -> String {
        RelativeTimeFormatter.label(now.addingTimeInterval(-secondsAgo), now: now)
    }

    // MARK: - Dakika bandı

    func testJustNowIsZeroMinutes() {
        XCTAssertEqual(label(secondsAgo: 0), "0m ago")
        XCTAssertEqual(label(secondsAgo: 59), "0m ago", "dakika tabana yuvarlanır")
    }

    func testMinutesUpToFiftyNine() {
        XCTAssertEqual(label(secondsAgo: 60), "1m ago")
        XCTAssertEqual(label(secondsAgo: 59 * 60), "59m ago")
    }

    // MARK: - Saat bandı

    func testExactlySixtyMinutesBecomesHours() {
        XCTAssertEqual(label(secondsAgo: 60 * 60), "1h ago")
        XCTAssertEqual(label(secondsAgo: 23 * 3600 + 3599), "23h ago")
    }

    // MARK: - Gün bandı

    func testTwentyFourHoursBecomesDays() {
        XCTAssertEqual(label(secondsAgo: 24 * 3600), "1d ago")
        XCTAssertEqual(label(secondsAgo: 47 * 3600), "1d ago", "gün tabana yuvarlanır")
        XCTAssertEqual(label(secondsAgo: 30 * 24 * 3600), "30d ago")
    }

    func testVeryOldCommitsStayInDays() {
        XCTAssertEqual(label(secondsAgo: 400 * 24 * 3600), "400d ago", "ay/yıl bandı YOK")
    }

    // MARK: - Gelecek tarih (saat kayması / bozuk commit tarihi)

    func testFutureDateClampsToZeroMinutes() {
        XCTAssertEqual(
            RelativeTimeFormatter.label(now.addingTimeInterval(3600), now: now),
            "0m ago",
            "negatif aralık max(0,·) ile kırpılır"
        )
    }
}

extension RelativeTimeFormatterTests {
    func testShortLabelBands() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RelativeTimeFormatter.shortLabel(now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(RelativeTimeFormatter.shortLabel(now.addingTimeInterval(-9 * 60), now: now), "9m")
        XCTAssertEqual(RelativeTimeFormatter.shortLabel(now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(RelativeTimeFormatter.shortLabel(now.addingTimeInterval(-2 * 86400), now: now), "2d")
        XCTAssertEqual(RelativeTimeFormatter.shortLabel(now.addingTimeInterval(60), now: now), "now", "gelecek tarih negatif olmaz")
    }
}
