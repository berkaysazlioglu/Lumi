import Foundation
import LumiKit

/// `~/.lumi` config + ui-state persistence servisi (design/02 §2, spec/13 §1).
///
/// Davranış paritesi: config her okumada diskten taze okunur (dış düzenlemeler
/// görünür); ui-state ilk dokunuştan sonra in-memory otoritedir ve disk yazımı
/// debounce'lanır (Electron'da renderer kopyası + 500ms debounce vardı).
/// Yazımlar ham-dict üzerine tipli-overlay merge'idir — bilinmeyen anahtarlar
/// korunur (karar 9, ConfigCodec açıklaması).
public actor ConfigService: ConfigServicing {
    public static let defaultWriteDebounce: Duration = .milliseconds(500)

    private let paths: LumiPaths
    private let writeDebounce: Duration
    private let broadcaster = EventBroadcaster<ConfigEvent>()

    private var cachedUIState: UIState?
    private var cachedUIRaw: [String: Any]?
    private var pendingUIFlush: Task<Void, Never>?

    public init(paths: LumiPaths, writeDebounce: Duration = ConfigService.defaultWriteDebounce) {
        self.paths = paths
        self.writeDebounce = writeDebounce
    }

    // MARK: - Config

    public func config() -> AppConfig {
        ConfigCodec.decodeConfig(from: readJSONObject(at: paths.configFile))
    }

    public func updateConfig(_ mutate: @Sendable (inout AppConfig) -> Void) throws {
        let raw = readJSONObject(at: paths.configFile)
        let old = ConfigCodec.decodeConfig(from: raw)
        var updated = old
        mutate(&updated)
        guard updated != old else { return }

        let merged = (raw ?? [:]).merging(ConfigCodec.configOverlay(updated)) { _, new in new }
        try writeJSONObject(merged, to: paths.configFile)
        broadcaster.send(.configChanged(old: old, new: updated))
    }

    public func isFirstRun() -> Bool {
        guard let raw = readJSONObject(at: paths.configFile) else { return true }
        return ConfigCodec.decodeConfig(from: raw).projectsRoot.isEmpty
    }

    // MARK: - UI State

    public func uiState() -> UIState {
        loadUIStateIfNeeded()
        return cachedUIState ?? .defaults
    }

    public func updateUIState(_ mutate: @Sendable (inout UIState) -> Void) {
        loadUIStateIfNeeded()
        var updated = cachedUIState ?? .defaults
        mutate(&updated)
        guard updated != cachedUIState else { return }
        cachedUIState = updated
        scheduleUIFlush()
    }

    public func flushPendingWrites() {
        pendingUIFlush?.cancel()
        pendingUIFlush = nil
        flushUIStateNow()
    }

    public func events() -> AsyncStream<ConfigEvent> {
        broadcaster.stream()
    }

    private func loadUIStateIfNeeded() {
        guard cachedUIState == nil else { return }
        let raw = readJSONObject(at: paths.uiStateFile)
        cachedUIRaw = raw
        cachedUIState = ConfigCodec.decodeUIState(from: raw)
    }

    private func scheduleUIFlush() {
        pendingUIFlush?.cancel()
        pendingUIFlush = Task { [writeDebounce] in
            try? await Task.sleep(for: writeDebounce)
            guard !Task.isCancelled else { return }
            await self.flushFromTask()
        }
    }

    private func flushFromTask() {
        flushUIStateNow()
    }

    private func flushUIStateNow() {
        guard let state = cachedUIState else { return }
        let merged = (cachedUIRaw ?? [:]).merging(ConfigCodec.uiStateOverlay(state)) { _, new in new }
        do {
            try writeJSONObject(merged, to: paths.uiStateFile)
            cachedUIRaw = merged
        } catch {
            // Debounce'lu arkaplan yazımı: kullanıcı akışını bloklamaz, iz bırakır
            fputs("[lumi] ui-state.json yazılamadı: \(error)\n", stderr)
        }
    }

    // MARK: - Disk I/O

    private func readJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            fputs("[lumi] parse hatası, defaults kullanılacak: \(url.lastPathComponent)\n", stderr)
            return nil
        }
        return dict
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        do {
            // withoutEscapingSlashes: Electron path'leri düz `/` ile yazar
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw LumiError.configIOFailed(
                file: url.lastPathComponent,
                detail: error.localizedDescription
            )
        }
    }
}
