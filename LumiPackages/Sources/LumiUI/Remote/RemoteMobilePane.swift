import LumiKit
import LumiState
import SwiftUI

/// Telefon eşleştirmesi: Mobile anahtarı, relay adresi, bağlantı durumu, QR ve
/// token yenileme (karar 22). Settings ▸ Remote ile Remote route'unun `Mobile`
/// sekmesi (karar 143) aynı görünümü paylaşır.
struct RemoteMobilePane: View {
    let remote: RemoteStore

    @State private var relayDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            Toggle(isOn: Binding(
                get: { remote.config.enabled },
                set: { value in Task { await remote.setEnabled(value) } }
            )) {
                Text("Mobile")
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Relay adresi")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("wss://…", text: $relayDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Typography.bodyMono)
                        .onSubmit { Task { await remote.setRelayUrl(relayDraft) } }
                    Button("Uygula") { Task { await remote.setRelayUrl(relayDraft) } }
                        .font(Theme.Typography.bodyMono)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(stateColor)
                    .frame(width: Theme.scaled(8), height: Theme.scaled(8))
                Text(stateLabel)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
            }

            if remote.config.enabled {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Eşleştirme QR'ı")
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.textSecondary)
                    if let qr = QRCodeRenderer.image(for: remote.pairingString) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: Theme.scaled(180), height: Theme.scaled(180))
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                    }
                    Text(remote.pairingString)
                        .font(Theme.Typography.captionMono)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                    Button("Token'ı yenile") { Task { await remote.regenerateToken() } }
                        .font(Theme.Typography.bodyMono)
                }
            }

        }
        .onAppear { relayDraft = remote.config.relayUrl }
    }

    // MARK: - Yardımcılar

    private var stateColor: Color {
        switch remote.state {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .red
        }
    }

    private var stateLabel: String {
        switch remote.state {
        case .connected: return "Bağlı"
        case .connecting: return "Bağlanıyor…"
        case .disconnected: return "Bağlı değil"
        }
    }
}
