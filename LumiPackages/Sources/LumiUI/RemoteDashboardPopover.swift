import CoreImage.CIFilterBuiltins
import LumiState
import SwiftUI

/// Topbar remote-dashboard popover'ı (design/06): start/stop + telefonla
/// bağlanmak için URL ve QR kod. Sunucu yalnız buradan yönetilir.
struct RemoteDashboardPopover: View {
    let store: RemoteDashboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.isRunning ? Color.green : Theme.textMuted)
                    .frame(width: 8, height: 8)
                Text("Remote Dashboard")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }

            if store.isRunning, let url = store.url {
                runningContent(url: url)
            } else {
                stoppedContent
            }

            toggleButton
        }
        .padding(14)
        .frame(width: 250)
        .background(Theme.bgElevated)
    }

    private func runningContent(url: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            if let qr = QRCodeRenderer.image(for: url) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity)
            }
            Text(url)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.accentPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
            Text("Telefonundan aynı Wi-Fi'dayken aç. Kimlik doğrulama yok — yalnız güvendiğin ağda çalıştır.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stoppedContent: some View {
        Text("Aktif terminalleri telefondan izlemek ve Claude'a yazmak için yerel ağ sunucusunu başlat.")
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toggleButton: some View {
        Button(action: { store.toggle() }) {
            Text(store.isBusy ? "…" : (store.isRunning ? "Stop" : "Start"))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(store.isRunning ? Theme.error : Theme.accentVivid)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
    }
}

/// URL → QR kod NSImage (CoreImage, harici bağımlılık yok). Piksel-keskin
/// kalması için çağıran taraf `.interpolation(.none)` uygular.
enum QRCodeRenderer {
    static func image(for string: String, size: CGFloat = 160) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
