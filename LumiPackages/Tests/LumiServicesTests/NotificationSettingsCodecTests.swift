import Foundation
import XCTest
import LumiKit
@testable import LumiServices

/// Karar 145: yeni anahtarlar additive; eski tekrar anahtarları korunur.
final class NotificationSettingsCodecTests: XCTestCase {
    func testLegacyDictionaryDecodesWithNewDefaultsAndRoundTripsOldKeys() throws {
        let legacy: [String: Any] = [
            "unseenEnabled": false, "unseenIntervalMinutes": 3,
            "seenEnabled": false, "seenIntervalMinutes": 9,
        ]
        let settings = NotificationSettingsCodec.decode(legacy)

        XCTAssertTrue(settings.agentFinished)
        XCTAssertTrue(settings.needsInput)
        XCTAssertTrue(settings.sound)

        let overlay = NotificationSettingsCodec.overlay(settings)
        XCTAssertEqual(overlay["unseenEnabled"] as? Bool, false)
        XCTAssertEqual(overlay["unseenIntervalMinutes"] as? Int, 3)
        XCTAssertEqual(overlay["seenEnabled"] as? Bool, false)
        XCTAssertEqual(overlay["seenIntervalMinutes"] as? Int, 9)
    }

    func testNewKeysDecode() {
        let settings = NotificationSettingsCodec.decode(["agentFinished": false, "needsInput": false, "sound": false])
        XCTAssertFalse(settings.agentFinished)
        XCTAssertFalse(settings.needsInput)
        XCTAssertFalse(settings.sound)
    }
}
