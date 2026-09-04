import Foundation
import LumiKit

/// `~/.lumi` config + ui-state persistence servisi (design/02 §2).
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
    /// Aynı bozuk dosya için tek yedek: `config()` her çağrıda diskten okur,
    /// yedekleme her okumada tekrarlanmamalı.
    private var backedUpFiles: Set<String> = []

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

    public nonisolated func events() -> AsyncStream<ConfigEvent> {
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
            self.flushFromTask()
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
            // Debounce'lu arkaplan yazımı: kullanıcı akışını bloklamaz ama
            // sessiz de kalmaz — iz + event (karar 5).
            let detail = (error as? LumiError)?.localizedDescription
                ?? error.localizedDescription
            fputs("[lumi] ui-state.json yazılamadı: \(detail)\n", stderr)
            broadcaster.send(.writeFailed(
                file: paths.uiStateFile.lastPathComponent,
                detail: detail
            ))
        }
    }

    // MARK: - Disk I/O

    private func readJSONObject(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            handleParseFailure(at: url)
            return nil
        }
        return dict
    }

    /// Bozuk dosya defaults'la EZİLMEDEN önce yanına kopyalanır: merge yalnız
    /// parse edilebilen ham sözlük üzerinden çalışır, parse edilemeyen dosyada
    /// bilinmeyen anahtarlar ilk yazımda kaybolurdu (karar 9 ihlali).
    private func handleParseFailure(at url: URL) {
        let detail: String
        if backedUpFiles.insert(url.path).inserted {
            let backup = url.deletingLastPathComponent().appendingPathComponent(
                "\(url.lastPathComponent).bak-\(Self.backupTimestamp())"
            )
            do {
                try FileManager.default.copyItem(at: url, to: backup)
                detail = "invalid JSON; backed up to \(backup.lastPathComponent)"
            } catch {
                detail = "invalid JSON; backup failed: \(error.localizedDescription)"
            }
        } else {
            detail = "invalid JSON"
        }
        fputs("[lumi] parse hatası, defaults kullanılacak: \(url.lastPathComponent) — \(detail)\n", stderr)
        broadcaster.send(.loadFailed(file: url.lastPathComponent, detail: detail))
    }

    private static func backupTimestamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: now)
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
