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

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
