import Foundation
import LumiKit
@testable import LumiServices
import XCTest

/// Karar 142: `config.json` → `claudeMods`; bool olmayan değer düşer, anahtar
/// yoksa boş (additive).
final class ClaudeModsCodecTests: XCTestCase {
    func testMissingKeyDecodesEmpty() {
        XCTAssertEqual(ConfigCodec.decodeConfig(from: [:]).claudeMods, [:])
    }

    func testKeepsBoolsAndDropsOtherValues() {
        let config = ConfigCodec.decodeConfig(from: [
            "claudeMods": ["a": true, "b": false, "c": "yes", "d": ["nested": true]],
        ])

        XCTAssertEqual(config.claudeMods, ["a": true, "b": false])
    }

    /// Karar 143 ek: paylaşım sırasında saklanan önceki mod durumları gidip gelir.
    func testHubSuspendedModsRoundTrip() {
        var config = AppConfig.defaults
        config.hubSuspendedClaudeMods = ["image-preview": true]
        let decoded = ConfigCodec.decodeConfig(from: ConfigCodec.configOverlay(config))
        XCTAssertEqual(decoded.hubSuspendedClaudeMods, ["image-preview": true])
        XCTAssertEqual(ConfigCodec.decodeConfig(from: [:]).hubSuspendedClaudeMods, [:])
    }
}
