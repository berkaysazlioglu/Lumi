import XCTest
@testable import LumiMobileKit

final class PairingTests: XCTestCase {

    // Mac-side generated string (RemoteStore.pairingString): ':' and '/' are also encoded.
    func testParseMacGeneratedPairingString() {
        let string = "lumi-remote://pair?url=wss%3A%2F%2Frelay.example.com&token=abcDEF123-_456789xyzABCDEF0123456789abcdefg&stoken=lrs_Srv-_Tok3n"
        let info = Pairing.parse(string)
        XCTAssertEqual(info, PairingInfo(
            relayUrl: "wss://relay.example.com",
            token: "abcDEF123-_456789xyzABCDEF0123456789abcdefg",
            serverToken: "lrs_Srv-_Tok3n"
        ))
    }

    func testParseTrimsWhitespace() {
        let string = "  lumi-remote://pair?url=wss%3A%2F%2Fr.example&token=0123456789abcdef&stoken=lrs_x\n"
        XCTAssertEqual(Pairing.parse(string)?.relayUrl, "wss://r.example")
    }

    func testParseRejectsInvalidInputs() {
        // wrong scheme / host
        XCTAssertNil(Pairing.parse("https://pair?url=wss%3A%2F%2Fr&token=0123456789abcdef"))
        XCTAssertNil(Pairing.parse("lumi-remote://settings?url=wss%3A%2F%2Fr&token=0123456789abcdef"))
        // missing parameter
        XCTAssertNil(Pairing.parse("lumi-remote://pair?token=0123456789abcdef"))
        XCTAssertNil(Pairing.parse("lumi-remote://pair?url=wss%3A%2F%2Fr.example"))
        // short token (protocol: ≥16)
        XCTAssertNil(Pairing.parse("lumi-remote://pair?url=wss%3A%2F%2Fr.example&token=kisa"))
        // relay url without ws(s)
        XCTAssertNil(Pairing.parse("lumi-remote://pair?url=https%3A%2F%2Fr.example&token=0123456789abcdef"))
        // plain text (Turkish; kept as-is — it is a parse input, not human text)
        XCTAssertNil(Pairing.parse("hic url degil"))
    }

    /// Decision 146: a link without a server token is an older Mac's — told apart from junk.
    func testLinkWithoutServerTokenIsFromAnOutdatedMac() {
        let old = "lumi-remote://pair?url=wss%3A%2F%2Fr.example&token=0123456789abcdef"
        XCTAssertEqual(Pairing.parseResult(old), .failure(.outdatedMac))
        XCTAssertEqual(Pairing.parseResult(old + "&stoken=a%20b"), .failure(.outdatedMac))
        XCTAssertEqual(Pairing.parseResult("hic url degil"), .failure(.invalid))
        XCTAssertTrue(Pairing.isPairingLink(old))
        XCTAssertFalse(Pairing.isPairingLink("hic url degil"))
    }

    func testInMemoryStoreRoundTrip() {
        let store = InMemorySecureStore()
        XCTAssertNil(store.read())
        let info = PairingInfo(relayUrl: "wss://r.example", token: "0123456789abcdef", serverToken: "lrs_test")
        store.write(info)
        XCTAssertEqual(store.read(), info)
        store.clear()
        XCTAssertNil(store.read())
    }
}
