import LumiKit
import LumiState
import SwiftUI

/// Uzaktan erişim ayarları: eşleştirme QR'ı, enable toggle, relay URL,
/// bağlantı durumu ve token yenileme (karar 22, spec/22 §5).
struct RemoteSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .remote

    @Shell private var shell

    init() {}

    private var remote: RemoteStore { shell.remote }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            LumiSectionTitle(
                title: "Remote",
                description: "Telefondan bağlan: QR'ı Lumi mobil uygulamasında okut. Mac'ten Mac'e ağ ve bu Mac'in hub olarak paylaşılması soldaki Remote'tadır; relay adresi ikisinde ortaktır."
            )

            RemoteMobilePane(remote: remote)

            Spacer()
        }
    }
}

#if DEBUG
#Preview("Remote") {
    SettingsTabPreview(.remote)
}
#endif
