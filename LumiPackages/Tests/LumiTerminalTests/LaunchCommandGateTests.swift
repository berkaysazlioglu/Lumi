import XCTest
@testable import LumiTerminal

@MainActor
final class LaunchCommandGateTests: XCTestCase {
    /// "Ateşlememeli" assert'lerinde sabit uyku kaçınılmaz; marj gate'in KENDİ
    /// sabitlerinden türetilir (magic number yok): en uzun iç bekleyişin katı
    /// dolduktan sonra hâlâ ateşlenmemişse, hiç ateşlenmeyecektir.
    private static let negativeAssertFactor = 3

    private func makeGate(
        quiet: Duration = .milliseconds(30),
        maxWait: Duration = .milliseconds(200)
    ) -> LaunchCommandGate {
        LaunchCommandGate(quietWindow: quiet, maxWait: maxWait)
    }

    /// Gate sabitlerine göre ifade edilen "hiçbir şey olmamalı" penceresi.
    private func negativeAssertWindow(quiet: Duration, maxWait: Duration) -> Duration {
        max(quiet, maxWait) * Self.negativeAssertFactor
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testFiresAfterQuietWindowFollowingOutput() async {
        // Arrange
        let gate = makeGate()
        var fired = 0
        gate.start { fired += 1 }

        // Act — shell prompt çıktısı geldi, sonra sessizlik
        gate.noteOutput()
        await waitUntil { fired > 0 }

        // Assert
        XCTAssertEqual(fired, 1)
    }

    func testOutputBurstsPostponeFiring() async {
        // Arrange
        let gate = makeGate(quiet: .milliseconds(60), maxWait: .seconds(5))
        var fired = 0
        gate.start { fired += 1 }

        // Act — 30ms aralıklı çıktı sürerken sessizlik penceresi (60ms) dolamaz.
        // Yavaş CI runner'da sleep 60ms'yi aşabilir; o durumda ateşleme meşrudur,
        // assert yalnız pencere içinde kalındıysa yapılır.
        for _ in 0..<4 {
            let start = ContinuousClock.now
            gate.noteOutput()
            try? await Task.sleep(for: .milliseconds(30))
            if ContinuousClock.now - start < .milliseconds(60) {
                XCTAssertEqual(fired, 0)
            }
        }
        await waitUntil { fired > 0 }

        // Assert — burst bitince tek atış
        XCTAssertEqual(fired, 1)
    }

    func testFiresAtMaxWaitEvenWithoutAnyOutput() async {
        // Arrange — hiç çıktı üretmeyen shell (edge)
        let gate = makeGate(quiet: .milliseconds(30), maxWait: .milliseconds(80))
        var fired = 0
        gate.start { fired += 1 }

        // Act
        await waitUntil { fired > 0 }

        // Assert
        XCTAssertEqual(fired, 1)
    }

    func testFiresExactlyOnce() async {
        // Arrange — hem sessizlik hem maxWait tetiklenebilecek senaryo
        let quiet = Duration.milliseconds(20)
        let maxWait = Duration.milliseconds(60)
        let gate = makeGate(quiet: quiet, maxWait: maxWait)
        var fired = 0
        gate.start { fired += 1 }

        // Act — ateşlemeyi POLLING ile bekle (sabit uyku yerine)
        gate.noteOutput()
        await waitUntil { fired > 0 }
        XCTAssertEqual(fired, 1)

        // Act — ateşten SONRA gelen çıktı yeniden tetiklememeli
        gate.noteOutput()
        try? await Task.sleep(for: negativeAssertWindow(quiet: quiet, maxWait: maxWait))

        // Assert
        XCTAssertEqual(fired, 1)
    }

    func testCancelPreventsFiring() async {
        // Arrange
        let quiet = Duration.milliseconds(20)
        let maxWait = Duration.milliseconds(50)
        let gate = makeGate(quiet: quiet, maxWait: maxWait)
        var fired = 0
        gate.start { fired += 1 }

        // Act — iptal sonrası hem quiet hem maxWait penceresi geçmiş olmalı
        gate.cancel()
        try? await Task.sleep(for: negativeAssertWindow(quiet: quiet, maxWait: maxWait))

        // Assert
        XCTAssertEqual(fired, 0)
    }
}
