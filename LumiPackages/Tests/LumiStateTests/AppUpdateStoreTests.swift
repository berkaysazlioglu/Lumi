import LumiKit
import LumiTestSupport
import XCTest
@testable import LumiState

@MainActor
final class AppUpdateStoreTests: XCTestCase {
    private func makeStore(
        current: String = "0.8.0",
        latest: String = "0.9.0",
        installer: FakeAppUpdateInstaller = FakeAppUpdateInstaller()
    ) -> (AppUpdateStore, FakeAppReleaseService) {
        let service = FakeAppReleaseService(outcome: .success(.fake(version: latest)))
        return (AppUpdateStore(currentVersion: current, service: service, installer: installer), service)
    }

    // MARK: - Kontrol (karar 102)

    func testSameOrOlderReleaseIsUpToDate() async {
        for latest in ["0.8.0", "0.7.6"] {
            let installer = FakeAppUpdateInstaller()
            let (store, _) = makeStore(latest: latest, installer: installer)
            await store.check()
            XCTAssertEqual(store.status, .upToDate(.fake(version: latest)), latest)
            XCTAssertNil(store.availableRelease)
            let prepared = await installer.preparedVersions
            XCTAssertEqual(prepared, [])
        }
    }

    /// `swift run` build'i sürüm taşımaz — "güncelle" denmez.
    func testDevelopmentBuildNeverClaimsAnUpdate() async {
        let (store, _) = makeStore(current: "dev", latest: "9.9.9")
        await store.check()
        XCTAssertEqual(store.status, .developmentBuild(.fake(version: "9.9.9")))
        XCTAssertNil(store.availableRelease)
    }

    func testFailureIsShownInline() async {
        let store = AppUpdateStore(
            currentVersion: "0.8.0",
            service: FakeAppReleaseService(outcome: .failure(.updateCheckFailed(detail: "offline"))),
            installer: FakeAppUpdateInstaller()
        )
        await store.check()
        XCTAssertEqual(store.status, .failed(message: "Could not check for updates: offline"))
        XCTAssertNotNil(store.lastCheckedAt)
    }

    // MARK: - İndirme (karar 118)

    func testNewerReleaseIsDownloadedAndReadyToInstall() async {
        let installer = FakeAppUpdateInstaller()
        let (store, _) = makeStore(installer: installer)
        await store.check()
        XCTAssertEqual(store.stagedUpdate?.release.version.description, "0.9.0")
        XCTAssertEqual(store.availableRelease?.version.description, "0.9.0")
        XCTAssertTrue(store.isCardVisible)
        XCTAssertNil(store.installTiming, "kurulum kendiliğinden seçilmez")
        let prepared = await installer.preparedVersions
        XCTAssertEqual(prepared, ["0.9.0"])
    }

    /// Yerel (Developer ID'siz) build release'le ezilmez ve kart nag'lemez.
    func testUnsignedBuildOnlyReportsAvailability() async {
        let installer = FakeAppUpdateInstaller(support: .unsignedBuild)
        let (store, _) = makeStore(installer: installer)
        await store.check()
        XCTAssertEqual(store.status, .available(.fake(version: "0.9.0")))
        XCTAssertFalse(store.isCardVisible)
        let prepared = await installer.preparedVersions
        XCTAssertEqual(prepared, [])
    }

    func testReadOnlyLocationShowsManualDownloadCard() async {
        let (store, _) = makeStore(installer: FakeAppUpdateInstaller(support: .readOnlyLocation(path: "/Volumes/x/Lumi.app")))
        await store.check()
        XCTAssertEqual(store.status, .available(.fake(version: "0.9.0")))
        XCTAssertTrue(store.isCardVisible)
    }

    func testDownloadFailureCanBeRetried() async {
        let installer = FakeAppUpdateInstaller(prepareError: .updateInstallFailed(detail: "checksum mismatch"))
        let (store, _) = makeStore(installer: installer)
        await store.check()
        XCTAssertEqual(
            store.status,
            .downloadFailed(.fake(version: "0.9.0"), message: "Update failed: checksum mismatch")
        )
        XCTAssertFalse(store.isCardVisible, "arka plan hatası kart açmaz")

        await installer.setPrepareError(nil)
        await store.retryDownload()
        XCTAssertNotNil(store.stagedUpdate)
    }

    /// Periyodik kontrol hazır sürümü yeniden indirmez, kartı söndürmez.
    func testRecheckKeepsReadyUpdateWithoutRedownloading() async {
        let installer = FakeAppUpdateInstaller()
        let (store, _) = makeStore(installer: installer)
        await store.check()
        await store.check()
        XCTAssertNotNil(store.stagedUpdate)
        let prepared = await installer.preparedVersions
        XCTAssertEqual(prepared, ["0.9.0"])
    }

    /// Hazır sürüm oturum boyunca sabittir: uçuştaki bir kontrol kullanıcının
    /// seçtiği/seçeceği sahneyi silemez. Daha yenisini bir sonraki açılış alır.
    /// Saha hatası: 0.9.0 hazırken 0.9.1 çıktı, Check for Updates onu hiç
    /// bulmuyordu. Daha yenisi indirilir, hazır olanın yerine geçer; eskisi
    /// ancak o zaman silinir.
    func testNewerReleaseReplacesStagedOne() async {
        let installer = FakeAppUpdateInstaller()
        let (store, service) = makeStore(installer: installer)
        await store.check()
        await service.setOutcome(.success(.fake(version: "0.9.1")))
        await store.check()
        XCTAssertEqual(store.stagedUpdate?.release.version.description, "0.9.1")
        XCTAssertFalse(store.isDownloadingNewer)
        let prepared = await installer.preparedVersions
        XCTAssertEqual(prepared, ["0.9.0", "0.9.1"])
        let discards = await installer.discards
        XCTAssertEqual(discards, ["0.9.0", "0.9.1"], "her hazır sürüm diğerlerini temizler")
    }

    /// Kurulum kaydedildiyse (Restart Now) kayıtlı sahne değiştirilmez.
    func testCommittedInstallIsNeverReplaced() async {
        let installer = FakeAppUpdateInstaller()
        let (store, service) = makeStore(installer: installer)
        await store.check()
        await store.restartNow()
        await service.setOutcome(.success(.fake(version: "0.9.1")))
        await store.check()
        XCTAssertEqual(store.stagedUpdate?.release.version.description, "0.9.0")
        let prepared = await installer.preparedVersions
        XCTAssertEqual(prepared, ["0.9.0"])
    }

    /// Daha yeninin indirmesi başarısızsa hazır olan kalır.
    func testFailedNewerDownloadKeepsReadyUpdate() async {
        let installer = FakeAppUpdateInstaller()
        let (store, service) = makeStore(installer: installer)
        await store.check()
        await installer.setPrepareError(.updateInstallFailed(detail: "offline"))
        await service.setOutcome(.success(.fake(version: "0.9.1")))
        await store.check()
        XCTAssertEqual(store.stagedUpdate?.release.version.description, "0.9.0")
        XCTAssertTrue(store.isCardVisible)
    }

    func testCheckFailureKeepsReadyUpdate() async {
        let (store, service) = makeStore()
        await store.check()
        await service.setOutcome(.failure(.updateCheckFailed(detail: "offline")))
        await store.check()
        XCTAssertNotNil(store.stagedUpdate)
    }

    func testDismissHidesCardForThatVersionOnly() async {
        let (store, service) = makeStore()
        await store.check()
        store.dismissCard()
        XCTAssertFalse(store.isCardVisible)
        XCTAssertNotNil(store.stagedUpdate, "segment dönüş yolu olarak kalır")

        await store.check()
        XCTAssertFalse(store.isCardVisible, "periyodik kontrol kapatılan kartı geri getirmez")

        await service.setOutcome(.success(.fake(version: "0.9.1")))
        await store.check()
        XCTAssertTrue(store.isCardVisible, "daha yeni sürüm kartı geri getirir")
    }

    // MARK: - Kurulum zamanı

    func testInstallOnQuitSchedulesWithoutRelaunch() async {
        let installer = FakeAppUpdateInstaller()
        let (store, service) = makeStore(installer: installer)
        await store.check()
        store.installOnQuit()
        XCTAssertEqual(store.installTiming, .onQuit)
        XCTAssertFalse(store.isCardVisible)

        // Seçim henüz kaydedilmedi: daha yenisi gelirse quit'te o kurulur.
        await service.setOutcome(.success(.fake(version: "0.9.1")))
        await store.check()
        XCTAssertEqual(store.stagedUpdate?.release.version.description, "0.9.1")
        XCTAssertEqual(store.installTiming, .onQuit)

        let scheduled = await store.installIfScheduled()
        XCTAssertTrue(scheduled)
        let calls = await installer.scheduled
        XCTAssertEqual(calls.map(\.version), ["0.9.1"])
        XCTAssertEqual(calls.map(\.relaunch), [false])
    }

    func testCancelledInstallOnQuitInstallsNothing() async {
        let installer = FakeAppUpdateInstaller()
        let (store, _) = makeStore(installer: installer)
        await store.check()
        store.installOnQuit()
        store.cancelScheduledInstall()
        let scheduled = await store.installIfScheduled()
        XCTAssertFalse(scheduled)
        let calls = await installer.scheduled
        XCTAssertTrue(calls.isEmpty)
    }

    /// Kurulum kapanıştan ÖNCE kaydedilir; kapanış yolu ikinci kez kaydetmez.
    func testRestartNowRegistersInstallBeforeQuitting() async {
        let installer = FakeAppUpdateInstaller()
        let (store, _) = makeStore(installer: installer)
        var scheduledAtRestart: [Bool] = []
        store.onRestartRequested = {
            Task { scheduledAtRestart = await installer.scheduled.map(\.relaunch) }
        }
        await store.check()
        await store.restartNow()
        XCTAssertEqual(store.installTiming, .restartNow)
        let installedAtShutdown = await store.installIfScheduled()
        XCTAssertFalse(installedAtShutdown)
        let calls = await installer.scheduled
        XCTAssertEqual(calls.map(\.relaunch), [true])
        await Task.yield()
        XCTAssertEqual(scheduledAtRestart, [true])
    }

    /// Kayıt başarısızsa Lumi kapanmaz — kapanıp hiç geri gelmemesi yerine hata kartta.
    func testRestartNowStaysOpenWhenRegistrationFails() async {
        let installer = FakeAppUpdateInstaller()
        await installer.setScheduleError(.updateInstallFailed(detail: "launchctl: 5"))
        let (store, _) = makeStore(installer: installer)
        var restartRequests = 0
        store.onRestartRequested = { restartRequests += 1 }
        await store.check()
        await store.restartNow()
        XCTAssertEqual(restartRequests, 0)
        XCTAssertNil(store.installTiming)
        XCTAssertEqual(store.lastInstallFailure, "Update failed: launchctl: 5")
        XCTAssertTrue(store.isCardVisible)
    }

    func testChoicesWithoutStagedUpdateAreIgnored() async {
        let (store, _) = makeStore(latest: "0.8.0")
        var restartRequests = 0
        store.onRestartRequested = { restartRequests += 1 }
        await store.check()
        store.installOnQuit()
        await store.restartNow()
        XCTAssertNil(store.installTiming)
        XCTAssertEqual(restartRequests, 0)
    }

    func testScheduleFailureIsRemembered() async {
        let installer = FakeAppUpdateInstaller()
        await installer.setScheduleError(.updateInstallFailed(detail: "launchctl bootstrap failed"))
        let (store, _) = makeStore(installer: installer)
        await store.check()
        store.installOnQuit()
        let scheduled = await store.installIfScheduled()
        XCTAssertFalse(scheduled)
        XCTAssertEqual(store.lastInstallFailure, "Update failed: launchctl bootstrap failed")
    }

    func testPreviousInstallFailureIsLoadedOnce() async {
        let installer = FakeAppUpdateInstaller(pendingFailure: "Copying the new version failed")
        let (store, _) = makeStore(installer: installer)
        await store.loadInstallFailure()
        XCTAssertEqual(store.lastInstallFailure, "Copying the new version failed")
        let again = await installer.consumeInstallFailure()
        XCTAssertNil(again)
    }

    /// Release geri çekilip `latest` mevcut sürüme ya da altına düşerse hazır
    /// sürüm, kart ve `Install on Quit` gider.
    func testWithdrawnReleaseDropsStagedUpdate() async {
        let installer = FakeAppUpdateInstaller()
        let (store, service) = makeStore(installer: installer)
        await store.check()
        store.installOnQuit()
        await service.setOutcome(.success(.fake(version: "0.8.0")))
        await store.check()
        XCTAssertEqual(store.status, .upToDate(.fake(version: "0.8.0")))
        XCTAssertNil(store.stagedUpdate)
        XCTAssertNil(store.installTiming)
        XCTAssertFalse(store.isCardVisible)
        let installed = await store.installIfScheduled()
        XCTAssertFalse(installed)
        let discards = await installer.discards
        XCTAssertEqual(discards, ["0.9.0", nil], "hazır olunca diğerleri, geri çekilince hepsi")
    }

    /// Hazırdan küçük ama mevcuttan büyük latest: geri çekilen atılır, latest indirilir.
    func testWithdrawnReleaseFallsBackToOlderNewerRelease() async {
        let installer = FakeAppUpdateInstaller()
        let (store, service) = makeStore(latest: "0.9.1", installer: installer)
        await store.check()
        await service.setOutcome(.success(.fake(version: "0.9.0")))
        await store.check()
        XCTAssertEqual(store.stagedUpdate?.release.version.description, "0.9.0")
        let prepared = await installer.preparedVersions
        XCTAssertEqual(prepared, ["0.9.1", "0.9.0"])
    }
}
