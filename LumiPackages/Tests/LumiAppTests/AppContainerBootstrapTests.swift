import Foundation
import XCTest
import LumiKit
import LumiState
import LumiTestSupport
@testable import LumiAppCore

/// Composition root'un boot sözleşmesi (design/00 §3, refactor 3.2/3.3/3.13).
///
/// `ServiceRegistry` sayesinde container artık TAMAMEN fake bir grafikle
/// kurulabilir; eski `XCTSkip` yerini gerçek sıralama assert'lerine bıraktı.
@MainActor
final class AppContainerBootstrapTests: XCTestCase {
    /// Bootstrap adımlarını sırasıyla kaydeden gözlemci assembly.
    private final class RecordingAssembly: FeatureAssembly {
        let bootstrapPhase: BootstrapPhase
        let name: String
        let log: BootstrapLog
        private(set) var didBuild = false

        init(_ name: String, phase: BootstrapPhase, log: BootstrapLog) {
            self.name = name
            self.bootstrapPhase = phase
            self.log = log
        }

        func build(services: any ServiceRegistry, shared: SharedStores) {
            didBuild = true
            log.append("build:\(name)")
        }

        func start() async {
            log.append("start:\(name)")
        }

        func shutdown() async {
            log.append("shutdown:\(name)")
        }
    }

    /// Yavaş assembly: bootstrap uçuştayken shutdown yarışını sürmek için.
    private final class SlowAssembly: FeatureAssembly {
        let bootstrapPhase = BootstrapPhase.ui
        let log: BootstrapLog
        let delay: Duration

        init(log: BootstrapLog, delay: Duration) {
            self.log = log
            self.delay = delay
        }

        func build(services: any ServiceRegistry, shared: SharedStores) {}

        func start() async {
            try? await Task.sleep(for: delay)
            log.append("start:slow")
        }

        func shutdown() async {
            log.append("shutdown:slow")
        }
    }

    private var registry: FakeServiceRegistry!
    private var shared: SharedStores!

    override func setUp() async throws {
        registry = FakeServiceRegistry()
        shared = SharedStores.make(
            config: registry.config,
            terminal: registry.terminal,
            toastAutoDismissAfter: 60
        )
    }

    override func tearDown() async throws {
        registry.removeTemporaryDirectories()
        registry = nil
        shared = nil
    }

    private func makeContainer(_ assemblies: [any FeatureAssembly]) -> AppContainer {
        AppContainer(services: registry, shared: shared, assemblies: assemblies)
    }

    // MARK: - Faz sırası

    /// Assembly'ler KAYIT sırasına değil, `BootstrapPhase` sırasına göre koşar;
    /// aynı fazdakiler kayıt sırasını korur (deterministik yan etki sırası).
    func testAssembliesStartInPhaseOrderRegardlessOfRegistrationOrder() async {
        let log = BootstrapLog()
        let ui = RecordingAssembly("ui", phase: .ui, log: log)
        let system = RecordingAssembly("system", phase: .system, log: log)
        let configB = RecordingAssembly("configB", phase: .config, log: log)
        let configA = RecordingAssembly("configA", phase: .config, log: log)
        let repo = RecordingAssembly("repo", phase: .repo, log: log)
        let container = makeContainer([ui, configB, configA, repo, system])

        await container.start()

        let starts = log.entries.filter { $0.hasPrefix("start:") }
        XCTAssertEqual(
            starts,
            ["start:system", "start:configB", "start:configA", "start:repo", "start:ui"]
        )
    }

    /// `build` init'te ve YİNE faz sırasında koşar; iş `start()`'a bırakılır
    /// (design/00 §3: "tüm servis + store'lar; henüz iş yapılmaz").
    func testBuildRunsForEveryAssemblyBeforeAnyStart() async {
        let log = BootstrapLog()
        let system = RecordingAssembly("system", phase: .system, log: log)
        let ui = RecordingAssembly("ui", phase: .ui, log: log)
        _ = makeContainer([ui, system])

        XCTAssertEqual(log.entries, ["build:system", "build:ui"])
        XCTAssertTrue(system.didBuild)
        XCTAssertTrue(ui.didBuild)
    }

    /// `shutdown()` faz sırasını TERSİNE çevirir: son kurulan ilk yıkılır.
    func testShutdownRunsInReversePhaseOrder() async {
        let log = BootstrapLog()
        let system = RecordingAssembly("system", phase: .system, log: log)
        let config = RecordingAssembly("config", phase: .config, log: log)
        let ui = RecordingAssembly("ui", phase: .ui, log: log)
        let container = makeContainer([system, config, ui])
        await container.start()

        await container.shutdown()

        let shutdowns = log.entries.filter { $0.hasPrefix("shutdown:") }
        XCTAssertEqual(shutdowns, ["shutdown:ui", "shutdown:config", "shutdown:system"])
    }

    // MARK: - Prelude sözleşmesi

    /// design/00 §3: `fixProcessPath()` HER spawn'dan ve SystemChecker'dan ÖNCE.
    func testFixProcessPathRunsBeforeAnyAssemblyStarts() async {
        let assembly = FixPathProbeAssembly(system: registry.fakeSystem)
        let container = makeContainer([assembly])

        await container.start()

        XCTAssertEqual(registry.fakeSystem.fixProcessPathCallCount, 1)
        XCTAssertEqual(
            assembly.fixCallCountAtStart, 1,
            "assembly başladığında PATH zaten düzeltilmiş olmalı"
        )
    }

    /// Prelude dizinleri oluşturur (karar 9: `~/.lumi` ağacı boot'ta hazır).
    func testPreludeCreatesConfigDirectories() async {
        let container = makeContainer([])

        await container.start()

        XCTAssertTrue(FileManager.default.fileExists(atPath: registry.paths.configDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: registry.paths.tempDir.path))
    }

    /// Kapanışta temp dizini silinir (Electron will-quit paritesi + karar 11).
    func testShutdownRemovesTempDirectoryAndFlushesConfig() async {
        let container = makeContainer([])
        await container.start()

        await container.shutdown()

        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.paths.tempDir.path))
        let flushes = await registry.fakeConfig.flushCount
        XCTAssertEqual(flushes, 1)
    }

    /// Paylaşılan store'lar assembly'lerden ÖNCE başlar, kapanışta assembly'lerden
    /// ÖNCE susar (quit yolundaki `killAll()` toast doğurmasın).
    func testSharedStoresStartBeforeAssembliesAndStopFirst() async {
        let log = BootstrapLog()
        let probe = SharedStoreProbeAssembly(shared: shared, log: log)
        let container = makeContainer([probe])

        await container.start()
        XCTAssertEqual(probe.terminalsRunningAtStart, true)

        await container.shutdown()
        XCTAssertEqual(probe.terminalsRunningAtShutdown, false)
    }

    // MARK: - 3.13 bootstrap/shutdown yarışı

    /// `shutdown()` uçuştaki bootstrap'i iptal eder ve BİTMESİNİ bekler —
    /// yarım kurulmuş graf üzerinde yıkım koşmaz.
    func testShutdownWaitsForInFlightBootstrap() async {
        let log = BootstrapLog()
        let slow = SlowAssembly(log: log, delay: .milliseconds(120))
        let container = makeContainer([slow])

        async let bootstrap: Void = container.start()
        try? await Task.sleep(for: .milliseconds(20)) // bootstrap uçuşta
        await container.shutdown()
        await bootstrap

        // shutdown, start bitmeden ÇALIŞMAMALI: kayıt sırası bunu kanıtlar.
        XCTAssertEqual(log.entries.last, "shutdown:slow")
        XCTAssertEqual(log.entries.filter { $0 == "shutdown:slow" }.count, 1)
    }

    func testStartIsIdempotent() async {
        let log = BootstrapLog()
        let assembly = RecordingAssembly("only", phase: .system, log: log)
        let container = makeContainer([assembly])

        await container.start()
        await container.start()

        XCTAssertEqual(log.entries.filter { $0 == "start:only" }.count, 1)
    }

    // MARK: - Paths

    /// Test/DEBUG build'i asla prod `~/.lumi` dizinine dokunmamalı (karar 9).
    /// Mod artık `#if DEBUG` ile container'da değil, `AppBootstrap`'te seçilir.
    func testDebugBuildsResolveDevelopmentPaths() {
        XCTAssertEqual(AppBootstrap.defaultPathsMode, .development, "testler DEBUG'ta koşar")

        let paths = LumiPaths(
            mode: AppBootstrap.defaultPathsMode,
            homeDirectory: URL(fileURLWithPath: "/fake/home")
        )
        XCTAssertEqual(paths.configDir.path, "/fake/home/.lumi-dev")
        XCTAssertEqual(paths.configFile.lastPathComponent, "config.json")
        XCTAssertEqual(paths.uiStateFile.lastPathComponent, "ui-state.json")
    }
}

// MARK: - Probe assembly'leri

/// Bootstrap adımlarının sıralı kaydı.
@MainActor
final class BootstrapLog {
    private(set) var entries: [String] = []
    func append(_ entry: String) { entries.append(entry) }
}

@MainActor
private final class FixPathProbeAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.system
    private let system: FakeSystemService
    private(set) var fixCallCountAtStart = -1

    init(system: FakeSystemService) {
        self.system = system
    }

    func build(services: any ServiceRegistry, shared: SharedStores) {}

    func start() async {
        fixCallCountAtStart = system.fixProcessPathCallCount
    }

    func shutdown() async {}
}

@MainActor
private final class SharedStoreProbeAssembly: FeatureAssembly {
    let bootstrapPhase = BootstrapPhase.system
    private let shared: SharedStores
    private let log: BootstrapLog
    private(set) var terminalsRunningAtStart: Bool?
    private(set) var terminalsRunningAtShutdown: Bool?

    init(shared: SharedStores, log: BootstrapLog) {
        self.shared = shared
        self.log = log
    }

    func build(services: any ServiceRegistry, shared: SharedStores) {}

    func start() async {
        terminalsRunningAtStart = shared.terminals.isConsuming
    }

    func shutdown() async {
        terminalsRunningAtShutdown = shared.terminals.isConsuming
    }
}
