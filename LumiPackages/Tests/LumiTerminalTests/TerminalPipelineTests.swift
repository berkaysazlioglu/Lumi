import Foundation
import LumiKit
import XCTest
@testable import LumiTerminal

/// Exit-cleanup sırası (design/01 §6) ve pipeline orkestrasyonu.
/// Pipeline io queue'ya confine'dır; testler tek thread'den sürdüğü için
/// sözleşme ihlal edilmez.
final class TerminalPipelineTests: XCTestCase {
    private func makePipeline() -> (TerminalPipeline, DispatchQueue) {
        let queue = DispatchQueue(label: "lumi.test.pipeline.\(UUID().uuidString)")
        return (TerminalPipeline(queue: queue), queue)
    }

    /// OSC 0 title'ı ile working'e geçen terminal, sıfır olmayan exit kodunda
    /// `.error`'a düşmeli (`statusMachine.onExit` gerçekten çağrılıyor mu?).
    func testFinishExitDrivesStatusMachineToErrorOnNonZeroCode() {
        let (pipeline, _) = makePipeline()
        let statuses = Recorder<TerminalStatus>()
        pipeline.onStatusChange = { statuses.append($0) }

        _ = pipeline.processOutput(Data("\u{1B}]0;Working on it\u{07}".utf8))
        XCTAssertEqual(pipeline.statusMachine.status, .working)

        pipeline.finishExit(code: 1)

        XCTAssertEqual(pipeline.statusMachine.status, .error)
        XCTAssertEqual(statuses.values.last, .error, "exit status'ü yayınlanmadı")
    }

    func testFinishExitDrivesStatusMachineToIdleOnZeroCode() {
        let (pipeline, _) = makePipeline()
        _ = pipeline.processOutput(Data("\u{1B}]0;Working on it\u{07}".utf8))

        pipeline.finishExit(code: 0)

        XCTAssertEqual(pipeline.statusMachine.status, .idle)
    }

    /// design/01 §6 adım 5: OSC buffer'ı silinir — yarım kalmış sequence exit'ten
    /// sonra tamamlanıp hayalet event üretmemeli.
    func testFinishExitClearsPartialOSCBuffer() {
        let (pipeline, _) = makePipeline()
        let titles = Recorder<String>()
        pipeline.onDisplayTitle = { titles.append($0) }

        // Sonlandırıcısı gelmemiş OSC 0 sequence'i
        _ = pipeline.processOutput(Data("\u{1B}]0;Half title".utf8))
        pipeline.finishExit(code: 0)
        _ = pipeline.processOutput(Data(" rest\u{07}".utf8))

        XCTAssertTrue(titles.values.isEmpty, "exit sonrası bayat OSC buffer'ı event üretti")
    }
}

/// Pipeline callback'leri `@Sendable`'dır; toplayıcı thread-safe olmalı.
private final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
