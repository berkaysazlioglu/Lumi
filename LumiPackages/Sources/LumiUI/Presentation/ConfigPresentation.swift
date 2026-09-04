import Foundation
import LumiKit

/// Config modellerinin UI metinleri (refactor 5.9).
extension GridLayout.HeightRatio {
    /// Grid ayarları popover'ındaki segmented etiketi.
    var displayLabel: String {
        switch self {
        case .full: return "100%"
        case .half: return "50%"
        case .third: return "33%"
        }
    }
}

/// Kullanım göstergesi aralık seçicisi (K38-A): seçenek KÜMESİ modeldeki
/// `UsageAutoRefresh.allowedIntervals`'tan türer, BİÇİM burada durur.
extension UsageAutoRefresh {
    static func intervalLabel(_ minutes: Int) -> String {
        "\(minutes) min"
    }
}

/// Terminal font boyutu ayarı: sınırların tek tanımı modeldeki
/// `AppConfig.terminalFontSizeRange`; ipucu metni ondan türer (refactor 5.7).
extension AppConfig {
    static var terminalFontSizeHint: String {
        let range = terminalFontSizeRange
        return "\(range.lowerBound)–\(range.upperBound)px; applies to all open terminals instantly"
    }
}
