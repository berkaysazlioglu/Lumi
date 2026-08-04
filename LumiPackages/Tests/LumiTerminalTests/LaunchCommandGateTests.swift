import XCTest
@testable import LumiTerminal

@MainActor
final class LaunchCommandGateTests: XCTestCase {
    private func makeGate(
        quiet: Duration = .milliseconds(30),
        maxWait: Duration = .milliseconds(200)
    ) -> LaunchCommandGate {
        LaunchCommandGate(quietWindow: quiet, maxWait: maxWait)
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

        // Act — 30ms aralıklı çıktı sürerken sessizlik penceresi (60ms) dolamaz
        for _ in 0..<4 {
            gate.noteOutput()
            try? await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(fired, 0)
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
        let gate = makeGate(quiet: .milliseconds(20), maxWait: .milliseconds(60))
        var fired = 0
        gate.start { fired += 1 }

        // Act
        gate.noteOutput()
        try? await Task.sleep(for: .milliseconds(150))
        gate.noteOutput() // ateşten SONRA gelen çıktı yeniden tetiklememeli

        // Assert
        await waitUntil { fired > 0 }
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(fired, 1)
    }

    func testCancelPreventsFiring() async {
        // Arrange
        let gate = makeGate(quiet: .milliseconds(20), maxWait: .milliseconds(50))
        var fired = 0
        gate.start { fired += 1 }

        // Act
        gate.cancel()
        try? await Task.sleep(for: .milliseconds(120))

        // Assert
        XCTAssertEqual(fired, 0)
    }
}
