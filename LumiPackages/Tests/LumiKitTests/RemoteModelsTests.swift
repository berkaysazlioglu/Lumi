import XCTest
@testable import LumiKit

final class RemoteModelsTests: XCTestCase {
    func testDefaults() {
        let d = RemoteConfig.defaults
        XCTAssertFalse(d.enabled)
        // Karar 146: Lumi'ye relay adresi gömülmez.
        XCTAssertEqual(d.relayUrl, "")
        XCTAssertEqual(d.token, "")
        XCTAssertNil(d.endpoint)
    }

    func testEndpointRequiresWebSocketAddressAndToken() {
        XCTAssertNotNil(RelayEndpoint(url: " wss://relay.example.com ", token: " lrs_x "))
        XCTAssertEqual(RelayEndpoint(url: "wss://relay.example.com", token: " lrs_x ")?.token, "lrs_x")
        XCTAssertNotNil(RelayEndpoint(url: "ws://127.0.0.1:8080", token: "t"))
        XCTAssertNil(RelayEndpoint(url: "https://relay.example.com", token: "t"))
        XCTAssertNil(RelayEndpoint(url: "relay.example.com", token: "t"))
        XCTAssertNil(RelayEndpoint(url: "wss://relay.example.com", token: ""))
        XCTAssertNil(RelayEndpoint(url: "wss://relay.example.com", token: "a b"))
    }

    func testRemoteFilePath() {
        let paths = LumiPaths(mode: .development)
        XCTAssertEqual(paths.remoteFile.lastPathComponent, "remote.json")
        XCTAssertEqual(paths.remoteFile.deletingLastPathComponent().path, paths.configDir.path)
    }
}
