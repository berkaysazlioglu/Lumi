import LumiKit
import SwiftUI

/// Karar 120: kartın ait olduğu projenin kimlik rengi — terminal → renk.
///
/// `terminalCheckoutLabels` (karar 103) kalıbı: renk kartın parametresi değil
/// yüzeyin ORTAMIdır. `TerminalsRouteView` sözlüğü hem repo route'unda hem All
/// Terminals'ta kurar; chrome (kenarlık), header (zemin + çubuk + etiket) ve
/// chip şeridi okur. Grid/maximize view'ları aradan geçirmek zorunda kalmaz —
/// ileride gelecek çoklu-proje görünümü aynı chrome'u kullanıp sözlüğü kurar.
/// Boş sözlük (varsayılan) = bugünkü görünüm.
private struct TerminalProjectColorsKey: EnvironmentKey {
    static let defaultValue: [TerminalID: ProjectColor] = [:]
}

extension EnvironmentValues {
    var terminalProjectColors: [TerminalID: ProjectColor] {
        get { self[TerminalProjectColorsKey.self] }
        set { self[TerminalProjectColorsKey.self] = newValue }
    }
}
