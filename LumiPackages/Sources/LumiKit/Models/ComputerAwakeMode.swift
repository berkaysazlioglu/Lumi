import Foundation

/// "Keep computer awake" modu (karar 43; Orca `ComputerAwakeMode` paritesi).
///
/// - `on`: sürekli uyanık tut.
/// - `auto` ("Agent"): en az bir terminal `working` durumundayken uyanık tut.
/// - `off`: sistemin uyku davranışına karışma.
///
/// Raw value'lar `config.json`'daki `computerAwakeMode` anahtarıyla birebir
/// aynıdır (karar 9, additive). Bilinmeyen değer `off`a düşer.
public enum ComputerAwakeMode: String, Sendable, Equatable, CaseIterable {
    case on
    case auto
    case off

    public static let `default` = ComputerAwakeMode.off

    /// Bilinmeyen/eksik raw değer default'a düşer (Orca `normalizeComputerAwakeMode`).
    public static func normalized(_ raw: String?) -> ComputerAwakeMode {
        raw.flatMap(ComputerAwakeMode.init(rawValue:)) ?? .default
    }

    public static let title = "Keep computer awake"

    /// Kısa etiket — alt bar segmenti ve menü satırı ("On" / "Agent" / "Off").
    public var label: String {
        switch self {
        case .on: return "On"
        case .auto: return "Agent"
        case .off: return "Off"
        }
    }

    /// Menü satırının alt açıklaması.
    public var detail: String {
        switch self {
        case .on: return "Keep this computer awake continuously"
        case .auto: return "Stay awake while an agent is working"
        case .off: return "Allow normal system sleep behavior"
        }
    }

    /// Uyku engeli şu an tutulmalı mı? `workingAgentCount` = `working`
    /// durumundaki terminal sayısı.
    public func isActive(workingAgentCount: Int) -> Bool {
        switch self {
        case .on: return true
        case .auto: return workingAgentCount > 0
        case .off: return false
        }
    }
}

/// Alt barda gösterilen anlık durum.
public struct ComputerAwakeStatus: Sendable, Equatable {
    public let mode: ComputerAwakeMode
    public let isActive: Bool

    public init(mode: ComputerAwakeMode, isActive: Bool) {
        self.mode = mode
        self.isActive = isActive
    }

    /// "Agent · Active" biçimindeki durum metni.
    public var text: String { "\(mode.label) · \(isActive ? "Active" : "Inactive")" }
}

/// "Also when lid is closed" anahtarının durumu (karar 122). Kaynak sistemin
/// kendisidir (`pmset -g` → `SleepDisabled`); Lumi yalnız kendi açtığını
/// (`AppConfig.lidSleepDisabledByLumi`) çıkışta geri alır.
public struct LidAwakeStatus: Sendable, Equatable {
    public var isOn: Bool
    /// Ayarı Lumi mi açtı (açıksa çıkışta geri alınır).
    public var isOwnedByLumi: Bool
    /// Önceki bir Lumi oturumundan geri alınamadan kalmış.
    public var isLeftover: Bool
    public var isPending: Bool
    public var isOnBattery: Bool
    public var errorMessage: String?

    public init(
        isOn: Bool = false, isOwnedByLumi: Bool = false, isLeftover: Bool = false,
        isPending: Bool = false, isOnBattery: Bool = false, errorMessage: String? = nil
    ) {
        self.isOn = isOn
        self.isOwnedByLumi = isOwnedByLumi
        self.isLeftover = isLeftover
        self.isPending = isPending
        self.isOnBattery = isOnBattery
        self.errorMessage = errorMessage
    }

    public static let title = "Also when lid is closed"
    public static let detail = "Turns off system sleep with pmset (asks for your admin password). Lumi turns it back off when you quit."
    /// Karar 122: On / Agent'ın kapsamadığı durumun dürüst notu.
    public static let lidNote = "On and Agent don't cover a closed lid: the Mac still sleeps unless it's on power with an external display."
    public static let batteryWarning = "On battery: a closed, awake Mac drains fast and can get hot in a bag."
    public static let leftoverNote = "Still on from a previous Lumi session."
    public static let externalNote = "Turned on outside Lumi: it stays on after quit."

    /// Satırın altındaki durum notu; öncelik hata > kalıntı > dışarıdan açılmış.
    public var note: String? {
        if let errorMessage { return errorMessage }
        if isLeftover { return Self.leftoverNote }
        if isOn && !isOwnedByLumi { return Self.externalNote }
        return nil
    }
}
