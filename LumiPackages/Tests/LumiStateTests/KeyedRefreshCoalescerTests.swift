import XCTest
@testable import LumiState

/// Uçuştaki bir yenileme sürerken gelen istekler tek bir "bir kez daha"ya
/// çöker (karar 28 — FSEvents üretici/tüketici hız farkında kuyruk şişmesi yok).
@MainActor
final class KeyedRefreshCoalescerTests: XCTestCase {
    private final class Gate: @unchecked Sendable {
        var continuations: [CheckedContinuation<Void, Never>] = []
        var runs: [String] = []
    }

    func testBurstDuringInFlightCollapsesToSingleFollowUp() async {
        let gate = Gate()
        let coalescer = KeyedRefreshCoalescer { key in
            gate.runs.append(key)
            await withCheckedContinuation { gate.continuations.append($0) }
        }

        coalescer.request("repo")
        await Task.yield()
        XCTAssertEqual(gate.runs, ["repo"])

        // Uçuşta iken 5 istek daha
        for _ in 0..<5 { coalescer.request("repo") }
        await Task.yield()
        XCTAssertEqual(gate.runs.count, 1, "uçuşta iken yeni tarama başlamaz")

        gate.continuations.removeFirst().resume()
        await waitUntil { gate.runs.count == 2 }
        XCTAssertEqual(gate.runs, ["repo", "repo"], "bitince tam olarak bir follow-up")

        gate.continuations.removeFirst().resume()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(gate.runs.count, 2, "kuyruk boşaldı, başka çalışma yok")
        XCTAssertFalse(coalescer.isInFlight("repo"))
    }

    func testDifferentKeysRunIndependently() async {
        let gate = Gate()
        let coalescer = KeyedRefreshCoalescer { key in
            gate.runs.append(key)
            await withCheckedContinuation { gate.continuations.append($0) }
        }

        coalescer.request("a")
        coalescer.request("b")
        await waitUntil { gate.runs.count == 2 }
        XCTAssertEqual(Set(gate.runs), ["a", "b"])
        for continuation in gate.continuations { continuation.resume() }
    }

    // MARK: - Reentrancy: perform İÇİNDEN aynı anahtar için istek

    /// `perform` kendi içinden `request(key)` çağırırsa (ör. tarama sırasında
    /// tetiklenen FSEvents) istek "pending"e düşer ve döngü bir kez daha koşar —
    /// sonsuz döngü değil, tam bir follow-up.
    func testRequestFromInsidePerformRunsExactlyOneFollowUp() async {
        let gate = Gate()
        var coalescer: KeyedRefreshCoalescer?
        coalescer = KeyedRefreshCoalescer { key in
            gate.runs.append(key)
            if gate.runs.count == 1 {
                // Uçuştaki drain'in İÇİNDEN yeniden istek
                coalescer?.request(key)
            }
        }

        coalescer?.request("repo")
        await waitUntil { gate.runs.count >= 2 }
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(gate.runs, ["repo", "repo"], "tam bir follow-up, fazlası değil")
        XCTAssertEqual(coalescer?.isInFlight("repo"), false, "döngü kapandı")
    }

    /// Her koşuda yeniden istek → sonlu bir tetikleyici sayısıyla sonlanmalı
    /// (her perform en fazla bir follow-up biriktirir).
    func testRepeatedReentrantRequestsDoNotCompound() async {
        let gate = Gate()
        var coalescer: KeyedRefreshCoalescer?
        let reentrantRuns = 3
        coalescer = KeyedRefreshCoalescer { key in
            gate.runs.append(key)
            if gate.runs.count <= reentrantRuns {
                // Aynı turda İKİ istek: ikincisi set'e ekleneceği için yutulur
                coalescer?.request(key)
                coalescer?.request(key)
            }
        }

        coalescer?.request("repo")
        await waitUntil { coalescer?.isInFlight("repo") == false && gate.runs.count > reentrantRuns }

        XCTAssertEqual(
            gate.runs.count, reentrantRuns + 1,
            "istekler set'te toplandığı için tur başına en fazla bir follow-up"
        )
    }

    func testReentrantRequestForAnotherKeyStartsItsOwnDrain() async {
        let gate = Gate()
        var coalescer: KeyedRefreshCoalescer?
        coalescer = KeyedRefreshCoalescer { key in
            gate.runs.append(key)
            if key == "a", gate.runs.count == 1 {
                coalescer?.request("b")
            }
        }

        coalescer?.request("a")
        await waitUntil { gate.runs.count >= 2 }
        XCTAssertEqual(Set(gate.runs), ["a", "b"])
        XCTAssertEqual(coalescer?.isInFlight("a"), false)
        XCTAssertEqual(coalescer?.isInFlight("b"), false)
    }

    func testIsInFlightIsFalseBeforeAnyRequest() {
        let coalescer = KeyedRefreshCoalescer { _ in }
        XCTAssertFalse(coalescer.isInFlight("repo"))
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
