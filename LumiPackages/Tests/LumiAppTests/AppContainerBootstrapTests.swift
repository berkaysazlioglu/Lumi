import Foundation
import XCTest
import LumiKit
@testable import LumiAppCore

/// Composition root'un boot sözleşmesinden BUGÜN test edilebilen kısım.
///
/// `AppContainer.init` hâlâ somut servisleri (ConfigService, TerminalSessionManager,
/// ClaudeUsageService…) kendi içinde kuruyor; `LumiPaths.Mode` de `#if DEBUG`
/// içine gömülü. Gerçek bootstrap testleri (sıra sözleşmesi, `start()`/`shutdown()`
/// simetrisi) `ServiceRegistry` + `FakeServiceRegistry` geldikten sonra
/// yazılabilir (plan 3.2). O yüzden burada yalnız enjekte edilebilir olan
/// parçalar doğrulanır — container gerçek servislerle KURULMAZ.
final class AppContainerBootstrapTests: XCTestCase {
    /// Test/DEBUG build'i asla prod `~/.lumi` dizinine dokunmamalı (karar 9).
    func testDebugBuildsResolveDevelopmentPaths() {
        #if DEBUG
        let mode = LumiPaths.Mode.development
        #else
        let mode = LumiPaths.Mode.production
        #endif
        XCTAssertEqual(mode, .development, "testler DEBUG'ta koşar → ~/.lumi-dev")

        let paths = LumiPaths(mode: mode, homeDirectory: URL(fileURLWithPath: "/fake/home"))
        XCTAssertEqual(paths.configDir.path, "/fake/home/.lumi-dev")
        XCTAssertEqual(paths.configFile.lastPathComponent, "config.json")
        XCTAssertEqual(paths.uiStateFile.lastPathComponent, "ui-state.json")
    }

    /// Bootstrap sırası (design/00 §3) bugün `AppContainer.start()` gövdesinde
    /// gömülü; kod tarafında kaymadığını görebileceğimiz tek nokta bu dosyadır.
    /// `ServiceRegistry`'den sonra bu test gerçek sıralama assert'ine dönüşecek.
    func testBootstrapContractIsDocumented() throws {
        throw XCTSkip(
            "AppContainer gerçek servisleri init'te kuruyor; sıra sözleşmesi "
            + "testi FakeServiceRegistry (plan 3.2) ile yazılacak."
        )
    }
}
