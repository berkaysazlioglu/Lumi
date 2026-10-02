import SwiftUI

/// Karar 103: kartın hangi checkout'a ait olduğu — repo yolu → görünen ad.
///
/// Repo görünümünde her kart aynı checkout'tadır ve etiket gürültüdür; All
/// Terminals'ta ise farklı projelerin kartları yan yana durur. Etiket bu
/// yüzden kartın parametresi değil yüzeyin ORTAMIdır: All Terminals sözlüğü
/// kurar, header ve chip şeridi okur; grid/maximize view'ları aradan geçirmek
/// zorunda kalmaz. Boş sözlük (varsayılan) = etiket yok.
private struct TerminalCheckoutLabelsKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

extension EnvironmentValues {
    var terminalCheckoutLabels: [String: String] {
        get { self[TerminalCheckoutLabelsKey.self] }
        set { self[TerminalCheckoutLabelsKey.self] = newValue }
    }
}
