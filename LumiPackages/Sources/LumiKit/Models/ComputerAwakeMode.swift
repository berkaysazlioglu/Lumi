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
