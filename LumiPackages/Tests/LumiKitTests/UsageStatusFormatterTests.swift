import Foundation
import XCTest
@testable import LumiKit

/// Kullanım durum metinlerinin SAF biçimlendirmesi (refactor 7.5): view'dan
/// çıkarıldı, `now` enjekte edilebildiği için deterministik test edilir.
final class UsageStatusFormatterTests: XCTestCase {
    private func window(resetsRaw: String, resetsAt: Date? = nil) -> UsageWindow {
        UsageWindow(percentUsed: 10, resetsAt: resetsAt, resetsRaw: resetsRaw, timezone: nil)
    }

    func testEmptyRawResetProducesNoText() {
        XCTAssertEqual(UsageStatusFormatter.resetText(for: window(resetsRaw: "")), "")
    }

    func testRawOnlyResetIsPrefixed() {
        XCTAssertEqual(
            UsageStatusFormatter.resetText(for: window(resetsRaw: "Jun 12 at 1:39pm")),
            "Resets: Jun 12 at 1:39pm"
        )
    }

    func testParsedResetAppendsRelativeSuffix() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let text = UsageStatusFormatter.resetText(
            for: window(resetsRaw: "Jun 12 at 1:39pm", resetsAt: now.addingTimeInterval(7200)),
            now: now
        )

        XCTAssertTrue(text.hasPrefix("Resets: Jun 12 at 1:39pm · "), text)
        XCTAssertTrue(text.contains("hour"), text)
    }

    func testClockTextIsTwentyFourHour() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 5
        components.hour = 14
        components.minute = 7
        let date = Calendar(identifier: .gregorian).date(from: components)!

        XCTAssertEqual(UsageStatusFormatter.clockText(date), "14:07")
    }
}
