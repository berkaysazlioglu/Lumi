import Foundation
import Testing
@testable import LumiKit

// Karar 143 ek: hub olarak paylaşılan Mac'te `image-preview` kapalı, paylaşım kapanınca
// önceki durumuna döner.
@Suite struct ClaudeModsHubTests {
    @Test func sharingTurnsTheModOffAndStoppingRestoresThePreviousValue() {
        var config = AppConfig.defaults
        config = ClaudeMods.applyingHubSharing(true, to: config)
        #expect(config.claudeMods["image-preview"] == false)
        #expect(config.hubSuspendedClaudeMods == ["image-preview": true])

        // Tekrarlanan olaylar idempotenttir; paylaşım sürerken elle açmak saklanan değeri bozmaz.
        config.claudeMods["image-preview"] = true
        config = ClaudeMods.applyingHubSharing(true, to: config)
        #expect(config.claudeMods["image-preview"] == true)

        config = ClaudeMods.applyingHubSharing(false, to: config)
        #expect(config.claudeMods["image-preview"] == true)
        #expect(config.hubSuspendedClaudeMods.isEmpty)
        #expect(ClaudeMods.applyingHubSharing(false, to: config) == config)
    }

    @Test func aModTheUserHadTurnedOffStaysOffAfterSharing() {
        var config = AppConfig.defaults
        config.claudeMods["image-preview"] = false
        config = ClaudeMods.applyingHubSharing(true, to: config)
        #expect(config.hubSuspendedClaudeMods == ["image-preview": false])
        config = ClaudeMods.applyingHubSharing(false, to: config)
        #expect(config.claudeMods["image-preview"] == false)
    }
}
