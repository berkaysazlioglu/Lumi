import Foundation
import XCTest
import LumiKit
import LumiTestSupport
@testable import LumiState

/// Karar 108: serbest terminal konumu — varsayılan home, seçim kalıcı,
/// silinmiş konumda terminal açılmaz.
@MainActor
final class LooseTerminalStoreTests: XCTestCase {
    private let home = "/Users/me"
    private var config: FakeConfigService!
    private var toasts: ToastStore!
    private var existing: Set<String> = []

    override func setUp() async throws {
        config = FakeConfigService()
        toasts = ToastStore()
        existing = [home, "/src", "/Users/me/Desktop"]
    }

    private func makeStore() -> LooseTerminalStore {
        LooseTerminalStore(
            config: config,
            toasts: toasts,
            home: home,
            directoryExists: { [unowned self] in self.existing.contains($0) }
        )
    }

    func testCurrentLocationDefaultsToHome() {
        let store = makeStore()
        XCTAssertEqual(store.currentLocation, home)
        XCTAssertEqual(store.currentLocationLabel, "~")
    }

    func testLoadedRecentDrivesCurrentLocation() {
        let store = makeStore()
        store.load(recent: ["~/Desktop", "/src"])
        XCTAssertEqual(store.currentLocation, "/Users/me/Desktop")
        XCTAssertEqual(store.currentLocationLabel, "~/Desktop")
    }

    func testSelectMakesLocationCurrentAndPersists() async {
        let store = makeStore()
        store.load(recent: ["/src"])

        store.select("~/Desktop")
        await store.flushPersistence()

        XCTAssertEqual(store.currentLocation, "/Users/me/Desktop")
        let persisted = await config.uiState().recentLooseLocations
        XCTAssertEqual(persisted, ["/Users/me/Desktop", "/src"])
    }

    func testSelectingCurrentLocationDoesNotWrite() async {
        let store = makeStore()
        store.load(recent: ["/src"])

        store.select("/src/")
        await store.flushPersistence()

        let writes = await config.uiStateUpdateCount
        XCTAssertEqual(writes, 0)
    }

    func testLocationForSpawnReturnsExistingDirectory() {
        let store = makeStore()
        store.load(recent: ["/src"])
        XCTAssertEqual(store.locationForSpawn(), "/src")
        XCTAssertTrue(toasts.toasts.isEmpty)
    }

    /// Silinmiş konumda terminal sessizce başka yerde açılmaz: uyarı + konum
    /// listeden düşer, sonraki deneme bir öncekine (ya da home'a) iner.
    func testMissingLocationWarnsAndIsForgotten() async {
        let store = makeStore()
        store.load(recent: ["/gone", "/src"])

        XCTAssertNil(store.locationForSpawn())
        await store.flushPersistence()

        XCTAssertEqual(toasts.toasts.map(\.kind), [.error])
        XCTAssertEqual(store.currentLocation, "/src")
        let persisted = await config.uiState().recentLooseLocations
        XCTAssertEqual(persisted, ["/src"])
    }

    func testCandidatesComeFromSourceRootsAndRecent() {
        let store = makeStore()
        store.load(recent: ["/Users/me/Desktop"])
        var appConfig = AppConfig.defaults
        appConfig.projectsRoot = "/src"

        XCTAssertEqual(
            store.candidates(for: appConfig).map(\.path),
            [home, "/src", "/Users/me/Desktop"]
        )
    }
}
