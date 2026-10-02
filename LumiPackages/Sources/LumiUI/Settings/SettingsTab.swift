import SwiftUI

/// Settings sekmesinin kimliği: sıra, ikon ve başlık (Faz 7.3).
///
/// Yeni bir sekme eklemek = `Tabs/` altında bir dosya + buraya bir `case`
/// (+ `content`'te bir satır). Panel kabuğu (`SettingsShell`) hiç değişmez.
public enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case agent
    case accounts
    case terminal
    case appearance
    case notifications
    case session
    case usage
    case shortcuts
    case remote
    /// Sürüm, sistem, linkler ve yeni sürüm kontrolü (karar 102). Hep en sonda.
    case about

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .agent: return "Agent"
        case .accounts: return "Accounts"
        case .terminal: return "Terminal"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        case .session: return "Session"
        case .usage: return "Usage"
        case .shortcuts: return "Shortcuts"
        case .remote: return "Remote"
        case .about: return "About"
        }
    }

    /// v1 lucide ikonlarının SF Symbol karşılığı.
    var icon: String {
        switch self {
        case .general: return "folder"
        case .agent: return "cpu"
        case .accounts: return "person.crop.circle"
        case .terminal: return "terminal"
        case .appearance: return "paintpalette"
        case .notifications: return "bell"
        case .session: return "clock.arrow.circlepath"
        case .usage: return "gauge.with.dots.needle.bottom.50percent"
        case .shortcuts: return "keyboard"
        case .remote: return "iphone.and.arrow.forward"
        case .about: return "info.circle"
        }
    }

    /// Sekmenin gövdesi. Her sekme kendi store'unu `@Shell`'den okur, bu yüzden
    /// burada parametre taşınmaz.
    @MainActor
    @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettingsTab()
        case .agent: AgentSettingsTab()
        case .accounts: AccountsSettingsTab()
        case .terminal: TerminalSettingsTab()
        case .appearance: AppearanceSettingsTab()
        case .notifications: NotificationsSettingsTab()
        case .session: SessionSettingsTab()
        case .usage: UsageSettingsTab()
        case .shortcuts: ShortcutsSettingsTab()
        case .remote: RemoteSettingsTab()
        case .about: AboutSettingsTab()
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
