import SwiftUI

/// Modal karartması + kapatma sözleşmesi (Faz 7.2).
///
/// Üç kopyası vardı ve üçü farklı karartma opaklığı kullanıyordu; tek karar:
/// **siyah %60**. Kapatmanın üç yolu da burada tek yerde toplanır — dışarı
/// tıklama, Escape ve (çağıranın çizdiği) kapatma butonu.
///
/// Karartma katmanı `accessibilityHidden`'dır: VoiceOver kullanıcısı için
/// kaçış yolu Escape'tir, "boş bir butonu bul ve bas" değil.
struct ModalOverlay<Content: View>: View {
    /// Tek karar: karartma opaklığı.
    static var scrimOpacity: Double { 0.6 }

    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(Self.scrimOpacity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            content()
        }
        .onExitCommand(perform: onDismiss)
    }
}

#if DEBUG
#Preview("ModalOverlay") {
    ModalOverlay(onDismiss: {}) {
        Panel(variant: .modal) {
            Text("Dialog content")
                .font(Theme.Typography.titleMono)
                .foregroundStyle(Theme.textPrimary)
                .padding(Theme.Spacing.xxxl)
        }
    }
    .frame(width: 480, height: 320)
    .background(Theme.bgDeep)
}
#endif
