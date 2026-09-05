import XCTest
@testable import LumiKit

/// Karar 43: `ps` tablosu ayrıştırma, alt ağaç toplamı ve biçimleyiciler.
final class ResourceUsageModelsTests: XCTestCase {
    private let ps = """
      1     0   0.0   1024
    100     1   2.5  40960
    200   100   1,5  20480
    201   100   0.0  10240
    300   200  10.0   4096
    400     1   0.0   2048
    garbage line
    """

    func testParseHandlesLocaleDecimalCommaAndSkipsGarbage() {
        let table = ProcessTable.parse(psOutput: ps)
        XCTAssertEqual(table.samples.count, 6)
        XCTAssertEqual(table.samples[200]?.cpuPercent, 1.5, "ondalık virgül noktaya çevrilir")
        XCTAssertEqual(table.samples[100]?.residentBytes, 40960 * 1024, "rss KB → byte")
        XCTAssertEqual(table.children[100]?.sorted(), [200, 201])
    }

    func testSubtreeMetricsSumRootAndDescendants() {
        let table = ProcessTable.parse(psOutput: ps)
        let metrics = table.subtreeMetrics(root: 100)
        XCTAssertEqual(metrics?.cpuPercent, 2.5 + 1.5 + 0.0 + 10.0)
        XCTAssertEqual(metrics?.residentBytes, UInt64(40960 + 20480 + 10240 + 4096) * 1024)
        XCTAssertNil(table.subtreeMetrics(root: 999), "tabloda olmayan kök = süreç bitmiş")
    }

    func testSubtreeSurvivesParentCycles() {
        let table = ProcessTable(samples: [
            ProcessSample(pid: 10, parentPID: 20, cpuPercent: 1, residentBytes: 1),
            ProcessSample(pid: 20, parentPID: 10, cpuPercent: 1, residentBytes: 1),
        ])
        XCTAssertEqual(table.subtreeMetrics(root: 10)?.cpuPercent, 2)
    }

    func testSnapshotSeparatesTerminalsFromAppHelpers() {
        // app 1 → terminal PTY 100 (alt ağacı 200/201/300), yardımcı 400
        let table = ProcessTable.parse(psOutput: ps)
        let terminalID = TerminalID()
        let snapshot = ResourceUsageSnapshot.make(
            table: table, appPID: 1, terminalRoots: [terminalID: 100],
            hostMemoryBytes: 16, sampledAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(snapshot.terminals[terminalID]?.residentBytes, UInt64(40960 + 20480 + 10240 + 4096) * 1024)
        XCTAssertEqual(snapshot.app.main.residentBytes, 1024 * 1024)
        XCTAssertEqual(snapshot.app.helpers.residentBytes, 2048 * 1024, "terminal ağacı yardımcılardan düşer")
        XCTAssertEqual(snapshot.terminalTotal.cpuPercent, 14.0)
    }

    func testFormattersMatchOrca() {
        XCTAssertEqual(ResourceUsageFormat.memory(512 * 1024), "512 KB")
        XCTAssertEqual(ResourceUsageFormat.memory(UInt64(1.5 * 1024 * 1024)), "1.5 MB")
        XCTAssertEqual(ResourceUsageFormat.memory(UInt64(2.25 * 1024 * 1024 * 1024)), "2.25 GB")
        XCTAssertEqual(ResourceUsageFormat.cpu(12.34), "12.3%")
    }
}
