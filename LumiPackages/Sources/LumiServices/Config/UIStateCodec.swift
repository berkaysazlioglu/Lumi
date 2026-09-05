import Foundation
import LumiKit

/// `~/.lumi/ui-state.json` kök nesnesi ↔ `UIState`.
///
/// Legacy/bilinmeyen anahtarlar (`gridColumns`, `activeView`) overlay'e GİRMEZ;
/// `ConfigService`'in ham-dict merge'i onları diskte aynen bırakır (karar 9).
enum UIStateCodec {
    static func decode(_ dict: [String: Any]?) -> UIState {
        var state = UIState.defaults
        guard let dict else { return state }

        if let value = dict["openTabs"] as? [Any] {
            state.openTabs = value.compactMap { $0 as? String }
        }
        if let value = dict["activeTab"] as? String {
            state.activeTab = value
        }
        if let value = JSONValue.bool(dict["leftSidebarOpen"]) {
            state.leftSidebarOpen = value
        }
        if let value = JSONValue.bool(dict["rightSidebarOpen"]) {
            state.rightSidebarOpen = value
        }
        if let layouts = dict["projectGridLayouts"] as? [String: Any] {
            state.projectGridLayouts = layouts.compactMapValues {
                GridLayoutCodec.decode($0 as? [String: Any])
            }
        }
        state.windowBounds = WindowBoundsCodec.decode(dict["windowBounds"] as? [String: Any])
        if let value = JSONValue.bool(dict["windowMaximized"]) {
            state.windowMaximized = value
        }
        // Karar 23 (additive): açılışta tüketilecek claude resume kayıtları
        if let raw = dict["resumeSessions"] as? [[String: Any]] {
            state.resumeSessions = raw.compactMap(ResumeSessionCodec.decode)
        }
        // K34 (additive): repo-dışı route kimliği. Yoksa nil → activeTab otoritedir.
        if let value = dict["activeRoute"] as? String {
            state.activeRoute = value
        }
        // K34 (additive): panel yerleşimi iki anahtardan okunur. `panelLayout`
        // yoksa nil kalır → LayoutStore eski bool'lardan migrate eder.
        state.panelLayout = PanelLayoutCodec.decode(
            dict["panelLayout"] as? [String: Any],
            visibleSlots: dict["visibleSlots"],
            fallbackLeftOpen: state.leftSidebarOpen,
            fallbackRightOpen: state.rightSidebarOpen
        )
        state.legacyGridColumns = GridLayoutCodec.decodeLegacyColumns(dict["gridColumns"])
        return state
    }

    static func overlay(_ state: UIState) -> [String: Any] {
        var overlay: [String: Any] = [
            // activeTab nil → açıkça null yazılır (gerçek dosya paritesi)
            "activeTab": state.activeTab ?? NSNull(),
            // K34 (additive): repo tab'ındayken null yazılır — koşullu yazım
            // bir önceki route'u diskte bayat bırakırdı (resumeSessions ile
            // aynı gerekçe). Legacy `activeView` anahtarına DOKUNULMAZ.
            "activeRoute": state.activeRoute ?? NSNull(),
            "openTabs": state.openTabs,
            "leftSidebarOpen": state.leftSidebarOpen,
            "rightSidebarOpen": state.rightSidebarOpen,
            "projectGridLayouts": state.projectGridLayouts.mapValues(GridLayoutCodec.overlay),
            // Karar 23: HER yazımda overlay'e girer — koşullu yazılsaydı merge
            // tüketilmiş (boşaltılmış) listeyi diskte bayat bırakırdı.
            "resumeSessions": state.resumeSessions.map(ResumeSessionCodec.overlay),
        ]
        // Opsiyoneller yalnız DOLU iken yazılır; nil'i `null` diye yazmak eski
        // dosyalarda olmayan bir anahtar üretirdi (karar 9).
        if let bounds = state.windowBounds {
            overlay["windowBounds"] = WindowBoundsCodec.overlay(bounds)
        }
        if let maximized = state.windowMaximized {
            overlay["windowMaximized"] = maximized
        }
        // K34 (additive): iki yeni anahtar birlikte yazılır. `leftSidebarOpen`/
        // `rightSidebarOpen` yukarıda ZATEN `visibleSlots`'un projeksiyonu olarak
        // yazıldı (karar 9) — eski Electron sürümü aynı dosyayı okumaya devam eder.
        if let layout = state.panelLayout {
            overlay["panelLayout"] = PanelLayoutCodec.overlay(layout)
            overlay["visibleSlots"] = PanelLayoutCodec.visibleSlotsOverlay(layout)
        }
        // legacyGridColumns YAZILMAZ: yalnız okuma yönlü migration girdisi;
        // ham `gridColumns` anahtarı merge'le diskte aynen kalır.
        return overlay
    }
}

/// `ui-state.json` → `panelLayout` + `visibleSlots` ↔ `PanelLayout` (K34).
///
/// İki ayrı anahtar kullanılır çünkü görünürlük eski `leftSidebarOpen`/
/// `rightSidebarOpen` bool'larıyla AYNI bilgidir ve tek başına okunabilir
/// kalmalıdır; yerleşim (slot içerikleri + genişlikler) ise yalnız Lumi
/// native'in bildiği additive bir yapıdır.
enum PanelLayoutCodec {
    static func decode(
        _ dict: [String: Any]?,
        visibleSlots: Any?,
        fallbackLeftOpen: Bool,
        fallbackRightOpen: Bool
    ) -> PanelLayout? {
        guard let dict else { return nil }
        let defaults = PanelLayout.defaults
        var slots = defaults.slots
        if let raw = dict["slots"] as? [String: Any] {
            for slot in PanelSlot.allCases {
                guard let ids = raw[slot.rawValue] as? [Any] else { continue }
                slots[slot] = ids.compactMap { ($0 as? String).map(PanelItemID.init(rawValue:)) }
            }
        }
        var widths = defaults.widths
        if let raw = dict["widths"] as? [String: Any] {
            for slot in PanelSlot.allCases {
                guard let value = JSONValue.double(raw[slot.rawValue]) else { continue }
                // K42: sağ yuvadaki eski sabit default yeni default'a taşınır.
                if slot == .right, value == PanelLayout.legacyProjectPanelWidth { continue }
                widths[slot] = value
            }
        }
        let visible: Set<PanelSlot>
        if let names = visibleSlots as? [Any] {
            visible = Set(names.compactMap { ($0 as? String).flatMap(PanelSlot.init(rawValue:)) })
        } else {
            // Yerleşim var ama görünürlük anahtarı yok → eski bool'lar otoritedir.
            visible = PanelLayout
                .migrating(leftOpen: fallbackLeftOpen, rightOpen: fallbackRightOpen)
                .visibleSlots
        }
        return PanelLayout(slots: slots, visibleSlots: visible, widths: widths)
    }

    static func overlay(_ layout: PanelLayout) -> [String: Any] {
        var slots: [String: Any] = [:]
        var widths: [String: Any] = [:]
        for slot in PanelSlot.allCases {
            slots[slot.rawValue] = layout.items(in: slot).map(\.rawValue)
            widths[slot.rawValue] = JSONNumber.integral(layout.width(for: slot))
        }
        return ["slots": slots, "widths": widths]
    }

    /// Deterministik sıra: `.sortedKeys` yalnız sözlükleri sıralar, diziyi değil.
    static func visibleSlotsOverlay(_ layout: PanelLayout) -> [String] {
        PanelSlot.allCases.filter(layout.isVisible).map(\.rawValue)
    }
}

/// Tam sayı değerler Electron gibi "580" yazılsın, "580.0" değil (karar 9).
enum JSONNumber {
    static func integral(_ value: Double) -> Any {
        value.truncatingRemainder(dividingBy: 1) == 0 ? Int(value) : value
    }
}

/// `ui-state.json` → `projectGridLayouts[*]` ↔ `GridLayout`.
enum GridLayoutCodec {
    static func decode(_ dict: [String: Any]?) -> GridLayout? {
        guard let dict,
              let modeRaw = dict["mode"] as? String,
              let count = JSONValue.int(dict["count"]) else {
            return nil
        }
        // Emekli `rows` modu → auto + fit migrasyonu (eski/v1 dosyaları).
        if modeRaw == "rows" {
            return GridLayout(mode: .auto, count: count, heightMode: .fit)
        }
        guard let mode = GridLayout.Mode(rawValue: modeRaw) else { return nil }
        // heightMode yoksa eski algılanan davranış: auto/columns scroll'du.
        let heightMode = (dict["heightMode"] as? String)
            .flatMap(GridLayout.HeightMode.init(rawValue:)) ?? .scroll
        let heightRatio = (dict["heightRatio"] as? String)
            .flatMap(GridLayout.HeightRatio.init(rawValue:)) ?? .half
        return GridLayout(mode: mode, count: count, heightMode: heightMode, heightRatio: heightRatio)
    }

    static func overlay(_ layout: GridLayout) -> [String: Any] {
        // mode/count korunur (karar 9), heightMode/heightRatio eklenir (additive).
        [
            "mode": layout.mode.rawValue,
            "count": layout.count,
            "heightMode": layout.heightMode.rawValue,
            "heightRatio": layout.heightRatio.rawValue,
        ]
    }

    /// Legacy global `gridColumns`: `"auto"` | sayı → migration girdisi.
    /// Yalnız OKUNUR; karşılığı overlay'de yoktur.
    static func decodeLegacyColumns(_ value: Any?) -> GridLayout? {
        guard let value else { return nil }
        if let text = value as? String {
            return text == "auto" ? GridLayout(mode: .auto, count: 2) : nil
        }
        guard let count = JSONValue.int(value) else { return nil }
        return GridLayout(mode: .columns, count: min(max(count, 2), 5))
    }
}

/// `ui-state.json` → `windowBounds` ↔ `WindowBounds`.
enum WindowBoundsCodec {
    static func decode(_ dict: [String: Any]?) -> WindowBounds? {
        guard let dict,
              let x = JSONValue.double(dict["x"]),
              let y = JSONValue.double(dict["y"]),
              let width = JSONValue.double(dict["width"]),
              let height = JSONValue.double(dict["height"]) else {
            return nil
        }
        return WindowBounds(x: x, y: y, width: width, height: height)
    }

    static func overlay(_ bounds: WindowBounds) -> [String: Any] {
        [
            "x": JSONNumber.integral(bounds.x),
            "y": JSONNumber.integral(bounds.y),
            "width": JSONNumber.integral(bounds.width),
            "height": JSONNumber.integral(bounds.height),
        ]
    }
}

/// `ui-state.json` → `resumeSessions[*]` ↔ `ResumeSession` (karar 23).
enum ResumeSessionCodec {
    static func decode(_ dict: [String: Any]?) -> ResumeSession? {
        guard let dict,
              let repoPath = dict["repoPath"] as? String,
              let sessionID = dict["sessionID"] as? String else {
            return nil
        }
        return ResumeSession(repoPath: repoPath, sessionID: sessionID)
    }

    static func overlay(_ session: ResumeSession) -> [String: Any] {
        [
            "repoPath": session.repoPath,
            "sessionID": session.sessionID,
        ]
    }
}
