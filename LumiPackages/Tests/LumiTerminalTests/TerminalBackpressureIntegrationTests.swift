import Foundation
import XCTest
@testable import LumiTerminal

/// Uçtan uca backpressure zinciri (design/00 Ek A §A.1-2, design/01 §3):
/// gerçek `PTYProcess` → `TerminalPipeline` (`FlowController` + `OutputCoalescer`)
/// → main hop → ack (`noteConsumed`) → `resumeReading`.
///
/// Birim testler (FlowControllerTests, OutputCoalescerTests) parçaları ayrı ayrı
/// doğrular; burada muhasebenin uçlarının tuttuğu kanıtlanır: produce HAM byte
/// sayar, consume BATCH byte sayar — ikisi farklı granülaritede olduğu için
/// yanlış eşleştirme kalıcı suspend (donmuş terminal) üretirdi.
final class TerminalBackpressureIntegrationTests: XCTestCase {
    private let env = ["TERM": "xterm-256color", "PATH": "/usr/bin:/bin"]

    /// Watermark'lar üretimin çok altında tutulur ki suspend/resume döngüsü
    /// birçok kez dönsün (gerçek değerler 512 KB / 128 KB).
    private static let highWatermark = 32 * 1024
    private static let lowWatermark = 8 * 1024
    private static let producedBytes = 400_000
    /// EOF'ta kernel buffer'ında kalan kuyruk atılabildiğinden hedef üretimin
    /// altında tutulur; kanıtlanan şey "akış tıkanmadı"dır.
    private static let deliveryTarget = 300_000
    private static let linePattern = "lumi\r\n" // tty ONLCR: \n → \r\n

    func testEndToEndSuspendResumeDeliversEveryByteInOrder() throws {
        // Arrange — kendi başına 400 KB üreten süreç
        let queue = DispatchQueue(label: "lumi.test.backpressure.\(UUID().uuidString)", qos: .utility)
        let flow = FlowController(
            highWatermark: Self.highWatermark,
            lowWatermark: Self.lowWatermark
        )
        let pipeline = TerminalPipeline(queue: queue, flow: flow)
        let stats = BackpressureStats()
        let pty = try PTYProcess(
            executable: "/bin/sh",
            args: ["-c", "yes lumi | head -c \(Self.producedBytes)"],
            cwd: "/tmp",
            env: env,
            initialCols: 80,
            initialRows: 24,
            queue: queue
        )
        let exited = expectation(description: "pty kapandı")
        pty.onExit = { _ in exited.fulfill() }
        defer {
            // Teardown sırası önemlidir: ASKIDA bir DispatchSource'u release etmek
            // libdispatch'te trap üretir ("Release of a suspended object"). Test
            // backpressure'ı bilerek tetiklediği için kaynak suspend'de bitebilir;
            // önce resume, sonra terminate, sonra exit beklenir — böylece
            // `cleanupIO` test hâlâ referansı tutarken koşar.
            // (PTYProcessTests.testSuspendStillWorksAfterResume ile aynı konvansiyon.)
            pty.resumeReading()
            pty.terminate()
            wait(for: [exited], timeout: 10)
        }

        let delivered = expectation(description: "hedef byte teslim edildi")
        delivered.assertForOverFulfill = false

        // deliver: TerminalSession.deliver'ın emülatörsüz ikizi — main hop + ack
        pipeline.onFlushBatch = { [weak pty] batch in
            hopToMain {
                stats.noteConsumed(batch)
                if flow.noteConsumed(batch.count) {
                    stats.noteResume()
                    pty?.resumeReading()
                }
                if stats.consumedBytes >= Self.deliveryTarget { delivered.fulfill() }
            }
        }
        pty.startReading { data in
            let directive = pipeline.processOutput(data)
            stats.noteProduced(data.count, suspended: directive == .suspend, inFlight: flow.inFlight)
            return directive
        }

        // Act — main runloop `wait` içinde pompalanır, hop'lar böyle koşar
        wait(for: [delivered], timeout: 20)

        // Assert — backpressure gerçekten devreye girdi ve geri açıldı
        XCTAssertGreaterThan(stats.suspendCount, 0, "hiç suspend olmadı — watermark'lar test edilmedi")
        XCTAssertGreaterThan(stats.resumeCount, 0, "hiç resume sinyali doğmadı")

        // Assert — in-flight sınırı: high watermark + en fazla bir okuma chunk'ı
        XCTAssertLessThanOrEqual(
            stats.maxInFlight,
            Self.highWatermark + PTYProcess.readChunkSize,
            "in-flight bellek sınırı aşıldı (backpressure sızdırıyor)"
        )

        // Assert — teslim edilen byte'lar sırasını ve bütünlüğünü korudu
        let text = stats.consumedText
        let expected = String(
            repeating: Self.linePattern,
            count: text.count / Self.linePattern.count + 1
        )
        XCTAssertEqual(
            text,
            String(expected.prefix(text.count)),
            "teslimatta byte kaybı veya sıra bozulması var"
        )
        XCTAssertGreaterThanOrEqual(stats.consumedBytes, Self.deliveryTarget)
    }
}

/// Produce (io queue) ve consume (MainActor) uçlarından dokunulur — kilitli.
private final class BackpressureStats: @unchecked Sendable {
    private let lock = NSLock()
    private var produced = 0
    private var consumed = Data()
    private var suspends = 0
    private var resumes = 0
    private var peakInFlight = 0

    func noteProduced(_ bytes: Int, suspended: Bool, inFlight: Int) {
        lock.lock()
        produced += bytes
        if suspended { suspends += 1 }
        peakInFlight = max(peakInFlight, inFlight)
        lock.unlock()
    }

    func noteConsumed(_ batch: Data) {
        lock.lock()
        consumed.append(batch)
        lock.unlock()
    }

    func noteResume() {
        lock.lock()
        resumes += 1
        lock.unlock()
    }

    var producedBytes: Int { withLock { produced } }
    var consumedBytes: Int { withLock { consumed.count } }
    var suspendCount: Int { withLock { suspends } }
    var resumeCount: Int { withLock { resumes } }
    var maxInFlight: Int { withLock { peakInFlight } }
    var consumedText: String { withLock { String(decoding: consumed, as: UTF8.self) } }

    private func withLock<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
