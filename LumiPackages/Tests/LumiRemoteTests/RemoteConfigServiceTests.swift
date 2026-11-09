import Foundation
import XCTest
import LumiKit
@testable import LumiRemote

final class RemoteConfigServiceTests: XCTestCase {
    private var tempHome: URL!
    private var paths: LumiPaths!

    override func setUp() {
        super.setUp()
        tempHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumi-remote-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        paths = LumiPaths(mode: .development, homeDirectory: tempHome)
        try! paths.ensureDirectoriesExist()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempHome)
        super.tearDown()
    }

    func testLoadWithoutFileReturnsDefaults() async {
        let service = RemoteConfigService(paths: paths)
        let config = await service.load()
        XCTAssertEqual(config, RemoteConfig.defaults)
    }

    func testSaveThenLoadRoundTrips() async {
        let service = RemoteConfigService(paths: paths)
        var config = RemoteConfig.defaults
        config.enabled = true
        config.token = "secret-token-1234567890"
        await service.save(config)
        let loaded = await service.load()
        XCTAssertEqual(loaded, config)
    }

    func testHubFieldsRoundTripAndOldFilesDefaultThem() async throws {
        let service = RemoteConfigService(paths: paths)
        // Hub alanları olmayan eski dosya varsayılanlara düşer (karar 9).
        try Data(#"{"enabled":true,"relayUrl":"wss://r.test","token":"tok"}"#.utf8).write(to: paths.remoteFile)
        let old = await service.load()
        XCTAssertEqual(old.serverToken, "")
        XCTAssertFalse(old.hubEnabled)

        var config = old
        config.serverToken = "lrs_server-token-1234567890"
        config.hubEnabled = true
        config.hubId = "hub-1"
        config.hubName = "Build Mac"
        await service.save(config)
        let loaded = await service.load()
        XCTAssertEqual(loaded, config)
    }

    /// Karar 146: eski gömülü Railway adresi kullanıcının seçimi sayılmaz; eski `networkToken`
    /// okunmaz ama dosyada korunur; dosya yalnız kullanıcıya açıktır (token'lar düz durur).
    func testLegacyRailwayUrlIsClearedAndNetworkTokenKept() async throws {
        let raw = #"{"enabled":true,"relayUrl":"wss://lumi-relay-production.up.railway.app","token":"tok","networkToken":"old-net-1234567890"}"#
        try Data(raw.utf8).write(to: paths.remoteFile)
        let service = RemoteConfigService(paths: paths)
        var config = await service.load()
        XCTAssertEqual(config.relayUrl, "")
        XCTAssertNil(config.endpoint)

        config.relayUrl = "wss://relay.example.com"
        config.serverToken = "lrs_abc"
        await service.save(config)
        let dict = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.remoteFile)) as! [String: Any]
        XCTAssertEqual(dict["networkToken"] as? String, "old-net-1234567890")
        XCTAssertEqual(dict["serverToken"] as? String, "lrs_abc")
        let attributes = try FileManager.default.attributesOfItem(atPath: paths.remoteFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let reloaded = await service.load()
        XCTAssertEqual(reloaded.endpoint, RelayEndpoint(url: URL(string: "wss://relay.example.com")!, token: "lrs_abc"))
    }

    func testEnsureTokenCreatesAStableHubId() async {
        let service = RemoteConfigService(paths: paths)
        let first = await service.ensureToken()
        XCTAssertFalse(first.hubId.isEmpty)
        let second = await service.ensureToken()
        XCTAssertEqual(second.hubId, first.hubId)
        XCTAssertEqual(second.token, first.token)
    }

    func testUnknownKeysPreservedOnSave() async throws {
        let raw = #"{"enabled": false, "relayUrl": "wss://x", "token": "t-1234567890123456", "futureKey": {"a": 1}}"#
        try raw.data(using: .utf8)!.write(to: paths.remoteFile)
        let service = RemoteConfigService(paths: paths)
        var config = await service.load()
        config.enabled = true
        await service.save(config)
        let dict = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.remoteFile)) as! [String: Any]
        XCTAssertNotNil(dict["futureKey"], "bilinmeyen anahtar korunmalı (karar 9)")
        XCTAssertEqual(dict["enabled"] as? Bool, true)
    }

    func testEnsureTokenGeneratesOnceAndPersists() async {
        let service = RemoteConfigService(paths: paths)
        let first = await service.ensureToken()
        XCTAssertGreaterThanOrEqual(first.token.count, 16)
        let second = await service.ensureToken()
        XCTAssertEqual(first.token, second.token, "mevcut token yeniden üretilmemeli")
    }

    func testGenerateTokenShapeAndUniqueness() {
        let a = generateToken()
        let b = generateToken()
        XCTAssertEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
        XCTAssertNil(a.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")), "base64url olmalı")
    }
}
