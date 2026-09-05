import SwiftUI

/// Settings sekmesinin kimliği: sıra, ikon ve başlık (Faz 7.3).
///
/// Yeni bir sekme eklemek = `Tabs/` altında bir dosya + buraya bir `case`
/// (+ `content`'te bir satır). Panel kabuğu (`SettingsShell`) hiç değişmez.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case terminal
    case appearance
    case notifications
    case session
    case usage
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .terminal: return "Terminal"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        case .session: return "Session"
        case .usage: return "Usage"
        case .shortcuts: return "Shortcuts"
        }
    }

    /// v1 lucide ikonlarının SF Symbol karşılığı.
    var icon: String {
        switch self {
        case .general: return "folder"
        case .terminal: return "terminal"
        case .appearance: return "paintpalette"
        case .notifications: return "bell"
        case .session: return "clock.arrow.circlepath"
        case .usage: return "gauge.with.dots.needle.bottom.50percent"
        case .shortcuts: return "keyboard"
        }
    }

    /// Sekmenin gövdesi. Her sekme kendi store'unu `@Shell`'den okur, bu yüzden
    /// burada parametre taşınmaz.
    @MainActor
    @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettingsTab()
        case .terminal: TerminalSettingsTab()
        case .appearance: AppearanceSettingsTab()
        case .notifications: NotificationsSettingsTab()
        case .session: SessionSettingsTab()
        case .usage: UsageSettingsTab()
        case .shortcuts: ShortcutsSettingsTab()
        }
    }
}

/// Bir sekme gövdesinin sözleşmesi: parametresiz kurulur (bağlamı
/// `@Shell`'den okur) ve hangi sekmeye ait olduğunu bilir.
///
/// `SettingsTab.content` bu sözleşmeyi elle kurar; protokol, sekmelerin
/// `init()`-edilebilir ve kendi kimliğini bilen birimler olduğunu test
/// edilebilir biçimde sabitler (`SettingsTabTests`).
@MainActor
protocol SettingsTabContent: View {
    static var tab: SettingsTab { get }
    init()
}
