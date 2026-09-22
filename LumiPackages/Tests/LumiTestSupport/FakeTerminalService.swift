import AppKit
import Foundation
import LumiKit

/// `TerminalServicing` fake'i (design/00 §3 test ikamesi deseni).
/// Tüm çağrılar kaydedilir; `failSpawns`/`failWrites` bayrakları hata yollarını
/// (karar 5: sessiz yutma yok) sürmek için ayrı bir sınıfa gerek bırakmaz.
@MainActor
public final class FakeTerminalService: TerminalServicing {
    private let broadcaster = EventBroadcaster<TerminalEvent>()

    // MARK: Ayarlanabilir davranış
    /// Açıkken `spawn` `.spawnFailed` fırlatır.
    public var failSpawns = false
    /// Açıkken `write` `.terminalNotFound` fırlatır (yazım kaydedilmez, deneme sayılır).
    public var failWrites = false
    /// Açıkken `kill` `.terminalNotFound` fırlatır.
    public var failKills = false
    /// `processID(for:)` yanıtları (Resource Manager testleri).
    public var processIDs: [TerminalID: Int32] = [:]

    // MARK: Çağrı kaydı
    public private(set) var spawnedMetas: [TerminalMeta] = []
    /// Spawn argümanları — meta komutu taşımadığı için ayrı kaydedilir.
    public private(set) var spawnCalls: [(
        repoPath: String, task: String?, command: String?, environment: [String: String]
    )] = []
    public private(set) var spawnAttempts = 0
    public private(set) var killedIDs: [TerminalID] = []
    public private(set) var killAllCount = 0
    public private(set) var shutdownCount = 0
    public private(set) var focusCalls: [TerminalID?] = []
    /// Yüzey durumu geçişleri (Faz 4.3): tekil (`id`) ve toplu (`repoPath`)
    /// çağrılar aynı sırada tek listede birikir.
    public private(set) var surfaceStateCalls: [SurfaceStateCall] = []
    public private(set) var windowFocusCalls: [Bool] = []
    public private(set) var resizeCalls: [(id: TerminalID, cols: Int, rows: Int)] = []
    public private(set) var writtenTexts: [(id: TerminalID, text: String)] = []
    public private(set) var writeAttempts = 0
    public private(set) var appliedFonts: [NSFont] = []
    public private(set) var appliedCursors: [(shape: TerminalCursorShape, blink: Bool)] = []

    /// Kaydedilen yüzey geçişi: tekil çağrıda `id`, toplu çağrıda `repoPath`
    /// dolu olur (`repoPath == nil` toplu çağrıda "tüm terminaller" demektir,
    /// bu yüzden iki alan ayrı tutulur).
    public struct SurfaceStateCall: Equatable, Sendable {
        public let state: TerminalSurfaceState
        public let id: TerminalID?
        public let repoPath: String?

        public init(state: TerminalSurfaceState, id: TerminalID?, repoPath: String?) {
            self.state = state
            self.id = id
            self.repoPath = repoPath
        }
    }

    public init() {}

    /// Kurulum gürültüsünü (spawn → focus) temizleyip yalnız test edilen
    /// adımın odak trafiğini görebilmek için.
    public func resetFocusCalls() {
        focusCalls = []
    }

    /// Aynı gerekçe yüzey geçişleri için (Faz 6.3 route turları).
    public func resetSurfaceStateCalls() {
        surfaceStateCalls = []
    }

    public var terminals: [TerminalMeta] { spawnedMetas }

    @discardableResult
    public func spawn(repoPath: String, task: String?, command: String?) throws -> TerminalMeta {
        try spawn(repoPath: repoPath, task: task, command: command, environment: [:])
    }

    @discardableResult
    public func spawn(
        repoPath: String,
        task: String?,
        command: String?,
        environment: [String: String]
    ) throws -> TerminalMeta {
        spawnAttempts += 1
        if failSpawns { throw LumiError.spawnFailed(reason: "fake") }
        let meta = TerminalMeta(
            id: TerminalID(),
            name: "Terminal \(spawnedMetas.count + 1)",
            repoPath: repoPath,
            createdAt: Date(),
            task: task,
            claudeSessionID: UUID().uuidString
        )
        spawnedMetas.append(meta)
        spawnCalls.append((repoPath, task, command, environment))
        broadcaster.send(.spawned(meta))
        return meta
    }

    public func write(id: TerminalID, text: String) throws {
        writeAttempts += 1
        if failWrites { throw LumiError.terminalNotFound(id) }
        writtenTexts.append((id, text))
    }

    public func kill(id: TerminalID) throws {
        if failKills { throw LumiError.terminalNotFound(id) }
        killedIDs.append(id)
    }

    public func processID(for id: TerminalID) -> Int32? {
        processIDs[id]
    }

    // MARK: Karar 45 — hook kablosu
    public private(set) var hookEndpoints: [AgentHookEndpoint?] = []
    public private(set) var appliedHookEvents: [AgentHookEvent] = []

    public func setAgentHookEndpoint(_ endpoint: AgentHookEndpoint?) {
        hookEndpoints.append(endpoint)
    }

    public private(set) var launchEnvironments: [AgentProvider: [String: String]] = [:]

    public func setLaunchEnvironment(_ environment: [String: String], for provider: AgentProvider) {
        launchEnvironments[provider] = environment
    }

    public func applyAgentHookEvent(_ event: AgentHookEvent) {
        appliedHookEvents.append(event)
    }

    public func killAll() {
        killAllCount += 1
    }

    /// Karar 90 testleri: gerçek serviste hook/exit'in `terminals`'a yaptığı
    /// değişikliği taklit eder — event'i yayınlamaz, çağıran `emit` eder.
    public func replaceSpawnedMeta(_ meta: TerminalMeta) {
        guard let index = spawnedMetas.firstIndex(where: { $0.id == meta.id }) else { return }
        spawnedMetas[index] = meta
    }

    public func removeSpawnedMeta(_ id: TerminalID) {
        spawnedMetas.removeAll { $0.id == id }
    }

    /// Gerçek servis global NSEvent monitörlerini bırakır; fake yalnız sayar.
    public func shutdown() {
        shutdownCount += 1
    }

    public func resize(id: TerminalID, cols: Int, rows: Int) {
        resizeCalls.append((id, cols, rows))
    }

    public func setFocused(_ id: TerminalID?) {
        focusCalls.append(id)
    }

    public func setWindowFocused(_ focused: Bool) {
        windowFocusCalls.append(focused)
    }

    public func setSurfaceState(_ state: TerminalSurfaceState, for id: TerminalID) {
        surfaceStateCalls.append(SurfaceStateCall(state: state, id: id, repoPath: nil))
    }

    public func setSurfaceState(_ state: TerminalSurfaceState, in repoPath: String?) {
        surfaceStateCalls.append(SurfaceStateCall(state: state, id: nil, repoPath: repoPath))
    }

    // MARK: TerminalAppearanceControlling

    public func applyFont(_ font: NSFont) {
        appliedFonts.append(font)
    }

    public func applyCursor(shape: TerminalCursorShape, blink: Bool) {
        appliedCursors.append((shape, blink))
    }

    /// Karar 57: uygulanan link-eylemi ayarlarının kaydı.
    public private(set) var appliedLinkActions: [Bool] = []

    public func applyLinkActions(enabled: Bool) {
        appliedLinkActions.append(enabled)
    }

    public func events() -> AsyncStream<TerminalEvent> {
        broadcaster.stream()
    }

    /// Testin senaryo event'i itmesi için.
    public func emit(_ event: TerminalEvent) {
        broadcaster.send(event)
    }

    // MARK: - Remote mirror

    private let remoteOutputBroadcaster = EventBroadcaster<Data>()

    public func subscribeOutput(_ id: TerminalID) -> AsyncStream<Data> {
        remoteOutputBroadcaster.stream()
    }

    public func writeInput(_ data: Data, to id: TerminalID) {}

    public func serializeScrollback(_ id: TerminalID) -> (data: Data, cols: Int, rows: Int) {
        (Data(), 0, 0)
    }
}
