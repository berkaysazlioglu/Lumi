import XCTest

@testable import LumiServices

final class ClaudeOAuthCredentialsTests: XCTestCase {
    func testExtractsAccessTokenFromCredentialsJSON() {
        let raw = #"{"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"r","expiresAt":1}}"#

        XCTAssertEqual(ClaudeOAuthCredentials.accessToken(fromJSON: raw), "tok-123")
    }

    func testIgnoresExpiryBecauseServerIsAuthoritative() {
        // Süresi geçmiş görünen token da döner: 401'i sunucu verir (Orca gerekçesi).
        let raw = #"{"claudeAiOauth":{"accessToken":"tok","expiresAt":0}}"#

        XCTAssertEqual(ClaudeOAuthCredentials.accessToken(fromJSON: raw), "tok")
    }

    func testReturnsNilWhenTokenMissingEmptyOrMalformed() {
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(fromJSON: #"{"claudeAiOauth":{}}"#))
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(
            fromJSON: #"{"claudeAiOauth":{"accessToken":"   "}}"#
        ))
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(fromJSON: #"{"other":1}"#))
        XCTAssertNil(ClaudeOAuthCredentials.accessToken(fromJSON: "not json"))
    }
}
