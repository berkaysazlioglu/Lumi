import Foundation
import LumiKit
import XCTest
@testable import LumiServices

/// Karar 114/123: orchestrator'ın gerçek haiku özetleri (monitoring'in
/// kaynağı). Token harcar ve ağ ister — yalnız `LUMI_LIVE_ORCHESTRATOR=1` ile koşar.
final class OrchestratorLiveTests: XCTestCase {
    /// Faz 4: gerçek haiku özeti JSON sözleşmesine uyuyor ve soruyu yakalıyor.
    func testHaikuDigestFollowsTheJSONContract() async throws {
        guard ProcessInfo.processInfo.environment["LUMI_LIVE_ORCHESTRATOR"] == "1" else {
            throw XCTSkip("canlı test: LUMI_LIVE_ORCHESTRATOR=1 ile koşar")
        }
        let message = """
        I refactored the authentication module: moved token refresh into `AuthSession`, \
        replaced the callback API with async/await, and updated 14 call sites. All 212 tests pass. \
        I also noticed the legacy `LoginViewController` still uses the old API, but changing it \
        touches the onboarding flow. Should I migrate `LoginViewController` too, or leave it for a \
        separate PR?
        """
        let digest = try await ClaudeDigestService().summarize(agentMessage: message, terminalTitle: "auth-refactor")
        XCTAssertFalse(digest.summary.isEmpty)
        XCTAssertTrue(digest.needsUser, "soru yakalanmadı: \(digest)")
        print("haiku digest:", digest.summary)
    }

    /// "Test etmedim" uyarısı soru sayılmaz.
    func testHaikuDigestDoesNotTreatACaveatAsAQuestion() async throws {
        guard ProcessInfo.processInfo.environment["LUMI_LIVE_ORCHESTRATOR"] == "1" else {
            throw XCTSkip("canlı test: LUMI_LIVE_ORCHESTRATOR=1 ile koşar")
        }
        let message = """
        Platform artık üstünde underground pipe varken açılmıyor. Derleme hatasız geçti ama oyun \
        içinde test etmedim.

        Sorun: PlatformBlockerEvaluateSystem platformu açmadan önce footprint'inde canlı pit, grinder \
        ve linear ivy olup olmadığına bakıyordu. Underground pipe bu listede yoktu.

        Değişiklikler:
        - PlatformBlockerEvaluateSystem.cs: UndergroundPipeTag taşıyan entity'lerin hücreleri de \
        engel sayılıyor; platform pipe kendini yok edene kadar kapalı kalıyor.
        - PlatformRules.cs: "Platform Without Top Pit" kuralı da aynı mantıkla çalışıyor.
        """
        let digest = try await ClaudeDigestService().summarize(agentMessage: message, terminalTitle: "platform-blocker")
        XCTAssertFalse(digest.needsUser, "uyarı soru sanıldı: \(digest)")
        print("haiku digest:", digest.summary)
    }

    /// Sonradan izlemeye alınan terminalin oturum özeti: hedef + son durum.
    func testHaikuSessionCatchUpFollowsTheJSONContract() async throws {
        guard ProcessInfo.processInfo.environment["LUMI_LIVE_ORCHESTRATOR"] == "1" else {
            throw XCTSkip("canlı test: LUMI_LIVE_ORCHESTRATOR=1 ile koşar")
        }
        let transcript = """
        [user] Add a dark mode toggle to the settings screen.
        [assistant] I'll add it to `SettingsView` and persist it in `UserDefaults`.
          · tool Edit Sources/Settings/SettingsView.swift
          · result: ok
          · tool Bash swift test
          · result: 48 passed
        [assistant] The toggle is in place and tests pass. Do you want the app to follow the \
        system appearance by default, or start in light mode?
        """
        let digest = try await ClaudeDigestService().summarizeSession(transcript: transcript, terminalTitle: "settings")
        XCTAssertFalse(digest.summary.isEmpty)
        XCTAssertTrue(digest.needsUser, "soru yakalanmadı: \(digest)")
        print("haiku catch-up:", digest.summary)
    }
}
