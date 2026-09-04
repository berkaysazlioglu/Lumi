import Foundation
import LumiKit
import XCTest
@testable import LumiTerminal

/// Exit-cleanup sırası (design/01 §6) ve pipeline orkestrasyonu.
/// Pipeline io queue'ya confine'dır; testler tek thread'den sürdüğü için
/// sözleşme ihlal edilmez. Zamanlayıcılar enjekte edilir → gerçek 16 ms / 3 sn
/// beklenmez, sıralama ve "resetlenmez" kuralları deterministik doğrulanır.
final class TerminalPipelineTests: XCTestCase {
    private func makePipeline() -> (TerminalPipeline, DispatchQueue) {
        let queue = DispatchQueue(label: "lumi.test.pipeline.\(UUID().uuidString)")
        return (TerminalPipeline(queue: queue), queue)
    }

    /// Enjekte edilmiş zamanlayıcılarla kurulum: coalescer ve silence timer ayrı
    /// sahte scheduler'lara bağlanır (hangi timer'ın dokunulduğu karışmasın).
    private func makeInstrumentedPipeline(
        flow: FlowController = FlowController()
    ) -> (
        pipeline: TerminalPipeline,
        coalescerScheduler: TestScheduler,
        silenceScheduler: TestScheduler
    ) {
        let queue = DispatchQueue(label: "lumi.test.pipeline.\(UUID().uuidString)")
        let coalescerScheduler = TestScheduler()
        let silenceScheduler = TestScheduler()
        let pipeline = TerminalPipeline(
            queue: queue,
            flow: flow,
            coalescerScheduler: coalescerScheduler,
            silenceScheduler: silenceScheduler
        )
        return (pipeline, coalescerScheduler, silenceScheduler)
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

    // MARK: - Chunk sırası: decoder → inferencer → OSC → status → coalescer

    /// design/01 §3'teki sıra: emülatöre teslim (coalescer flush) status/title
    /// yayınından SONRA gelir. Aynı chunk içinde status önce hesaplanır; teslim
    /// ayrı bir zamanlayıcı turunda olur.
    func testStatusAndTitleAreEmittedBeforeEmulatorDelivery() {
        // Arrange
        let (pipeline, coalescerScheduler, _) = makeInstrumentedPipeline()
        let order = Recorder<String>()
        pipeline.onStatusChange = { _ in order.append("status") }
        pipeline.onDisplayTitle = { _ in order.append("title") }
        pipeline.onFlushBatch = { _ in order.append("flush") }

        // Act
        _ = pipeline.processOutput(Data("\u{1B}]0;Building app\u{07}".utf8))
        XCTAssertEqual(order.values, ["title", "status"], "OSC/status chunk anında işlenmeli")
        coalescerScheduler.fire()

        // Assert
        XCTAssertEqual(order.values, ["title", "status", "flush"])
    }

    /// Coalescer HAM byte alır (emülatör byte ister) — decode edilmiş metin değil.
    /// Chunk sınırında bölünmüş çok-byte karakter de bozulmadan birleşmeli.
    func testCoalescerReceivesRawBytesEvenWhenSplitMidCharacter() {
        // Arrange — ✳ (U+2733) 3 byte; ikinci byte'ta bölünür
        let (pipeline, coalescerScheduler, _) = makeInstrumentedPipeline()
        let batches = Recorder<Data>()
        pipeline.onFlushBatch = { batches.append($0) }
        let full = Data("\u{1B}]0;\u{2733} idle\u{07}".utf8)
        let splitIndex = full.count - 8

        // Act
        _ = pipeline.processOutput(full.prefix(splitIndex))
        _ = pipeline.processOutput(full.suffix(from: splitIndex))
        coalescerScheduler.fire()

        // Assert — teslim edilen byte'lar girişin birebir aynısı
        XCTAssertEqual(batches.values, [full])
    }

    // MARK: - Codex sessizlik zamanlayıcısı

    func testCodexOutputTouchesSilenceTimerAndSilenceDropsStatusToWaiting() {
        // Arrange — hint output'tan çıkarılır
        let (pipeline, _, silenceScheduler) = makeInstrumentedPipeline()

        // Act
        _ = pipeline.processOutput(Data("OpenAI Codex v0.1\n".utf8))

        // Assert — aktivite: working + timer kuruldu
        XCTAssertEqual(pipeline.currentHint, .codex)
        XCTAssertEqual(pipeline.statusMachine.status, .working)
        XCTAssertEqual(silenceScheduler.scheduleCount, 1)
        XCTAssertEqual(silenceScheduler.lastInterval, CodexSilenceTimer.defaultInterval)

        // Act — 3 sn sessizlik
        silenceScheduler.fire()

        // Assert — odaklı değil → waitingUnseen
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)
    }

    /// TerminalPipeline ~62: turn-complete GÖRÜLEN chunk'ta silence timer
    /// resetlenmez ve aktivite işlenmez — aksi halde "bitti" sinyali aynı chunk
    /// içinde anında geri alınırdı (status tekrar working'e sıçrardı).
    func testTurnCompleteChunkNeitherRestartsSilenceTimerNorReassertsWorking() {
        // Arrange — codex hint'i + çalışır durum
        let (pipeline, _, silenceScheduler) = makeInstrumentedPipeline()
        _ = pipeline.processOutput(Data("OpenAI Codex ready\n".utf8))
        XCTAssertEqual(pipeline.statusMachine.status, .working)
        let schedulesBefore = silenceScheduler.scheduleCount

        // Act — turn-complete bildirimi ve ardından gelen çıktı AYNI chunk'ta
        _ = pipeline.processOutput(Data("\u{1B}]9;Turn complete\u{07}trailing output\n".utf8))

        // Assert — timer yeniden kurulmadı, iptal edildi; status waiting'de kaldı
        XCTAssertEqual(silenceScheduler.scheduleCount, schedulesBefore, "turn-complete chunk'ı timer'ı resetledi")
        XCTAssertGreaterThan(silenceScheduler.cancelCount, 0, "turn-complete timer'ı iptal etmedi")
        XCTAssertFalse(silenceScheduler.isScheduled)
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)
    }

    /// Turn-complete'ten SONRAKİ chunk normal işlenir (kural chunk-yereldir).
    func testOutputAfterTurnCompleteChunkRestartsSilenceTimer() {
        let (pipeline, _, silenceScheduler) = makeInstrumentedPipeline()
        _ = pipeline.processOutput(Data("OpenAI Codex ready\n".utf8))
        _ = pipeline.processOutput(Data("\u{1B}]9;Turn complete\u{07}".utf8))
        let schedulesBefore = silenceScheduler.scheduleCount

        _ = pipeline.processOutput(Data("new work\n".utf8))

        XCTAssertEqual(silenceScheduler.scheduleCount, schedulesBefore + 1)
        XCTAssertEqual(pipeline.statusMachine.status, .working)
    }

    /// `applyHint(.codex)` OSC 9 üzerinden gelir: hint codex'e sabitlenir ve
    /// aynı yolda timer iptal edilir.
    func testOSCTurnCompleteAppliesCodexHint() {
        let (pipeline, _, silenceScheduler) = makeInstrumentedPipeline()

        _ = pipeline.processOutput(Data("\u{1B}]9;task finished\u{07}".utf8))

        XCTAssertEqual(pipeline.currentHint, .codex)
        XCTAssertEqual(silenceScheduler.cancelCount, 1)
    }

    /// Hint claude'a dönerse timer iptal edilir (Claude tamamen title-tabanlıdır).
    func testClaudeHintCancelsSilenceTimer() {
        // Arrange — önce codex, timer kurulu
        let (pipeline, _, silenceScheduler) = makeInstrumentedPipeline()
        _ = pipeline.processOutput(Data("OpenAI Codex ready\n".utf8))
        XCTAssertTrue(silenceScheduler.isScheduled)

        // Act — ✳ prefix'li title claude hint'i taşır
        _ = pipeline.processOutput(Data("\u{1B}]0;\u{2733} idle\u{07}".utf8))

        // Assert — asimetri: hint codex'ten düşmez, ama title claude hint'i
        // OSC yoluyla geldiğinde applyOSCHint onu ezer ve timer iptal edilir
        XCTAssertEqual(pipeline.currentHint, .claude)
        XCTAssertFalse(silenceScheduler.isScheduled)
        XCTAssertGreaterThan(silenceScheduler.cancelCount, 0)
    }

    // MARK: - OSC → status / karar bekliyor

    func testOSCTitleDrivesDisplayTitleAndWorkingStatus() {
        // Arrange
        let (pipeline, _, _) = makeInstrumentedPipeline()
        let titles = Recorder<String>()
        let statuses = Recorder<TerminalStatus>()
        pipeline.onDisplayTitle = { titles.append($0) }
        pipeline.onStatusChange = { statuses.append($0) }

        // Act — çalışan title, ardından ✳ idle title'ı
        _ = pipeline.processOutput(Data("\u{1B}]2;* Refactoring\u{07}".utf8))
        _ = pipeline.processOutput(Data("\u{1B}]2;\u{2733} Done\u{07}".utf8))

        // Assert — `/^.\s*/` paritesi: ilk karakter + boşluk soyulur
        XCTAssertEqual(titles.values, ["Refactoring", "Done"])
        XCTAssertEqual(statuses.values, [.working, .waitingUnseen])
    }

    func testPermissionRequestRaisesAwaitingDecisionWithoutTouchingStatus() {
        // Arrange
        let (pipeline, _, _) = makeInstrumentedPipeline()
        let decisions = Recorder<Bool>()
        let statuses = Recorder<TerminalStatus>()
        pipeline.onAwaitingDecisionChange = { decisions.append($0) }
        pipeline.onStatusChange = { statuses.append($0) }

        // Act — izin promptu
        _ = pipeline.processOutput(Data("\u{1B}]9;Claude needs your permission\u{07}".utf8))

        // Assert — yalnız ayrı sinyal; 6 durumlu makineye dokunulmaz
        XCTAssertEqual(decisions.values, [true])
        XCTAssertTrue(pipeline.decisionTracker.isAwaitingDecision)
        XCTAssertTrue(statuses.values.isEmpty, "izin promptu status'ü değiştirdi")

        // Act — çalışmaya dönüş promptun kapandığını gösterir
        _ = pipeline.processOutput(Data("\u{1B}]0;Editing file\u{07}".utf8))

        // Assert
        XCTAssertEqual(decisions.values, [true, false])
        XCTAssertEqual(statuses.values, [.working])
    }

    // MARK: - Yazma yolu

    func testProcessInputStripsFocusEventsAndInfersHint() {
        // Arrange
        let (pipeline, _, _) = makeInstrumentedPipeline()

        // Act — mode 1004 focus event'i tek başına yazılırsa hiçbir şey kalmaz
        let focusOnly = pipeline.processInput(Data("\u{1B}[I".utf8))
        let mixed = pipeline.processInput(Data("\u{1B}[Ocodex\u{1B}[I".utf8))

        // Assert
        XCTAssertTrue(focusOnly.isEmpty, "focus event PTY'ye sızdı")
        XCTAssertEqual(mixed, Data("codex".utf8))
        XCTAssertEqual(pipeline.currentHint, .codex)
    }

    func testCarriageReturnWithCodexHintMarksWorking() {
        // Arrange — codex hint'i + waiting durumu
        let (pipeline, _, silenceScheduler) = makeInstrumentedPipeline()
        _ = pipeline.processOutput(Data("OpenAI Codex ready\n".utf8))
        silenceScheduler.fire()
        XCTAssertEqual(pipeline.statusMachine.status, .waitingUnseen)

        // Act — kullanıcı Enter'a bastı
        _ = pipeline.processInput(Data("go\r".utf8))

        // Assert — codex heuristiği: Enter = çalışmaya başladı
        XCTAssertEqual(pipeline.statusMachine.status, .working)
    }

    func testCarriageReturnWithoutCodexHintDoesNotForceWorking() {
        // Claude tarafında status yalnız title'dan sürülür (asimetri).
        let (pipeline, _, _) = makeInstrumentedPipeline()
        _ = pipeline.processOutput(Data("\u{1B}]0;\u{2733} idle\u{07}".utf8))
        let statusBefore = pipeline.statusMachine.status

        _ = pipeline.processInput(Data("hello\r".utf8))

        XCTAssertEqual(pipeline.statusMachine.status, statusBefore)
    }

    // MARK: - Backpressure ve exit

    func testProcessOutputReturnsSuspendAtHighWatermark() {
        // Arrange — küçük watermark'larla aynı muhasebe
        let flow = FlowController(highWatermark: 128, lowWatermark: 32)
        let (pipeline, _, _) = makeInstrumentedPipeline(flow: flow)

        // Assert — produce ham byte sayar
        XCTAssertEqual(pipeline.processOutput(Data(repeating: 0x61, count: 64)), .proceed)
        XCTAssertEqual(pipeline.processOutput(Data(repeating: 0x61, count: 64)), .suspend)
        XCTAssertEqual(flow.inFlight, 128)
    }

    /// `prepareForExit` (io tarafı, design/01 §6 ilk yarısı): timer iptal +
    /// karar sinyali sıfırlanır + coalescer'da bekleyen byte'lar boşaltılır.
    func testPrepareForExitFlushesCoalescerAndCancelsTimer() {
        // Arrange
        let (pipeline, coalescerScheduler, silenceScheduler) = makeInstrumentedPipeline()
        let batches = Recorder<Data>()
        let decisions = Recorder<Bool>()
        pipeline.onFlushBatch = { batches.append($0) }
        pipeline.onAwaitingDecisionChange = { decisions.append($0) }
        _ = pipeline.processOutput(Data("OpenAI Codex\u{1B}]9;needs your permission\u{07}".utf8))
        XCTAssertTrue(batches.values.isEmpty, "timer dolmadan teslim edilmemeli")

        // Act
        pipeline.prepareForExit()

        // Assert — kalan byte'lar tek batch olarak teslim, timer iptal, karar sıfır
        XCTAssertEqual(batches.values.count, 1)
        XCTAssertEqual(
            batches.values.first,
            Data("OpenAI Codex\u{1B}]9;needs your permission\u{07}".utf8)
        )
        XCTAssertFalse(coalescerScheduler.isScheduled)
        XCTAssertFalse(silenceScheduler.isScheduled)
        XCTAssertEqual(decisions.values, [true, false])
    }

    // MARK: - Faz 4.8: semantik katman enjeksiyonu (OCP)

    /// Yeni bir OSC semantiği (burada OSC 7 = cwd) mevcut hiçbir tipe
    /// dokunmadan pipeline'a takılabilmeli. Bugün OSC 7 hiçbir varsayılan
    /// semantik tarafından tanınmıyor — eklendiğinde tanınıyor.
    func testNewSemanticsCanBePluggedInWithoutTouchingExistingCode() {
        // Arrange — önce varsayılan zincir: OSC 7 yok sayılır
        let (defaultPipeline, _) = makePipeline()
        let ignoredTitles = Recorder<String>()
        defaultPipeline.onDisplayTitle = { ignoredTitles.append($0) }
        _ = defaultPipeline.processOutput(Data("\u{1B}]7;file:///tmp/lumi\u{07}".utf8))
        XCTAssertTrue(ignoredTitles.values.isEmpty, "OSC 7 varsayılan zincirde tanınmamalı")

        // Act — aynı pipeline'a yeni semantik enjekte edilir
        let queue = DispatchQueue(label: "lumi.test.pipeline.\(UUID().uuidString)")
        let extended = TerminalPipeline(
            queue: queue,
            semantics: OSCSemanticsDefaults.all + [CwdSemantics()]
        )
        let titles = Recorder<String>()
        extended.onDisplayTitle = { titles.append($0) }
        _ = extended.processOutput(Data("\u{1B}]7;file:///tmp/lumi\u{07}".utf8))

        // Assert — yeni kod yalnız EKLENDİ; mevcut semantikler bozulmadı
        XCTAssertEqual(titles.values, ["file:///tmp/lumi"])
        let claudeTitles = Recorder<String>()
        extended.onDisplayTitle = { claudeTitles.append($0) }
        _ = extended.processOutput(Data("\u{1B}]0;\u{2733} done\u{07}".utf8))
        XCTAssertEqual(claudeTitles.values, ["done"])
    }

    // MARK: - Faz 4.2: donma gözetimi

    /// In-flight byte var ve feed gelmiyorsa heartbeat donmayı yayınlar;
    /// teslim (ack) gelince düzelme sinyali gider.
    func testWatchdogStallSignalIsPublishedAndRecovered() {
        // Arrange
        let queue = DispatchQueue(label: "lumi.test.pipeline.\(UUID().uuidString)")
        let clock = TestClock()
        let heartbeat = TestHeartbeat()
        let flow = FlowController()
        let pipeline = TerminalPipeline(
            queue: queue,
            flow: flow,
            coalescerScheduler: TestScheduler(),
            silenceScheduler: TestScheduler(),
            watchdogHeartbeat: heartbeat,
            clock: clock
        )
        let stalls = Recorder<Bool>()
        pipeline.onStallChange = { stalls.append($0) }

        // Act — okundu (in-flight), ama emülatöre teslim edilmedi
        _ = pipeline.processOutput(Data(repeating: 0x61, count: 4096))
        clock.advance(by: FeedWatchdog.defaultStallThreshold + 0.5)
        heartbeat.tick()
        XCTAssertEqual(stalls.values, [true])

        // Act — teslim gerçekleşti (ack) → düzelme
        pipeline.watchdog.noteFeed(duration: 0.001)
        flow.noteConsumed(4096)

        XCTAssertEqual(stalls.values, [true, false])
    }

    func testPrepareForExitStopsWatchdogHeartbeat() {
        let queue = DispatchQueue(label: "lumi.test.pipeline.\(UUID().uuidString)")
        let heartbeat = TestHeartbeat()
        let pipeline = TerminalPipeline(
            queue: queue,
            coalescerScheduler: TestScheduler(),
            silenceScheduler: TestScheduler(),
            watchdogHeartbeat: heartbeat
        )
        XCTAssertTrue(heartbeat.isRunning, "watchdog init'te başlamalı")

        pipeline.prepareForExit()

        XCTAssertFalse(heartbeat.isRunning, "exit'te heartbeat durmadı (timer sızıntısı)")
    }
}

/// Test-only semantik: OSC 7 (cwd) → başlık olayı. Üretim kodunda karşılığı
/// yoktur; amaç genişletilebilirliği kanıtlamaktır.
private struct CwdSemantics: OSCSemantics {
    func interpret(code: Int, payload: String, hint: AgentHint) -> [OSCEvent] {
        guard code == 7, !payload.isEmpty else { return [] }
        return [.title(OSCTitleEvent(
            rawTitle: payload,
            displayTitle: payload,
            isWorking: nil,
            providerHint: nil
        ))]
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
