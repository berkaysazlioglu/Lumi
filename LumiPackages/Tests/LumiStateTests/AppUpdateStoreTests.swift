import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

@MainActor
final class AppUpdateStoreTests: XCTestCase {
    func testNewerReleaseIsAvailable() async {
        let store = AppUpdateStore(
            currentVersion: "0.8.0",
            service: FakeAppReleaseService(outcome: .success(.fake(version: "0.9.0")))
        )
        await store.check()
        XCTAssertEqual(store.availableRelease?.version.description, "0.9.0")
        XCTAssertNotNil(store.lastCheckedAt)
    }

    func testSameOrOlderReleaseIsUpToDate() async {
        for latest in ["0.8.0", "0.7.6"] {
            let store = AppUpdateStore(
                currentVersion: "0.8.0",
                service: FakeAppReleaseService(outcome: .success(.fake(version: latest)))
            )
            await store.check()
            XCTAssertEqual(store.status, .upToDate(.fake(version: latest)), latest)
            XCTAssertNil(store.availableRelease)
        }
    }

    /// `swift run` build'i sürüm taşımaz — "güncelle" denmez.
    func testDevelopmentBuildNeverClaimsAnUpdate() async {
        let store = AppUpdateStore(
            currentVersion: "dev",
            service: FakeAppReleaseService(outcome: .success(.fake(version: "9.9.9")))
        )
        await store.check()
        XCTAssertEqual(store.status, .developmentBuild(.fake(version: "9.9.9")))
        XCTAssertNil(store.availableRelease)
    }

    func testFailureIsShownInline() async {
        let store = AppUpdateStore(
            currentVersion: "0.8.0",
            service: FakeAppReleaseService(outcome: .failure(.updateCheckFailed(detail: "offline")))
        )
        await store.check()
        XCTAssertEqual(store.status, .failed(message: "Could not check for updates: offline"))
    }
}
