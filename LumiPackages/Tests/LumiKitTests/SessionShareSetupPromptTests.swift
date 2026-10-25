import LumiKit
import XCTest

/// Karar 138: protokolün kanonik metni setup prompt'udur — istemcinin
/// beklediği her uç, alan ve hata kodu metinde geçmeli.
final class SessionShareSetupPromptTests: XCTestCase {
    func testPromptDeclaresEveryEndpointFieldAndErrorCode() {
        let text = SessionShareSetupPrompt.text
        let required = [
            "GET /lumi/sessions/v1`", "GET /lumi/sessions/v1/sessions`", "GET /lumi/sessions/v1/sessions/{id}",
            "POST /lumi/sessions/v1/sessions", "DELETE /lumi/sessions/v1/sessions/{id}",
            #""protocol": "lumi-sessions""#, #""version": 1"#, "\"me\"", "maxUploadBytes",
            "\"id\"", "\"title\"", "\"project\"", "\"provider\"", "\"uploader\"", "\"uploadedAt\"", "\"size\"",
            "\"archive\"", "nextCursor", "lumi-agent-session",
            "unauthorized", "forbidden", "not_found", "payload_too_large", "validation_failed", "not_configured",
            "Authorization: Bearer", "add-user", "64 MB",
        ]
        for fragment in required {
            XCTAssertTrue(text.contains(fragment), "setup prompt is missing \(fragment)")
        }
    }
}
