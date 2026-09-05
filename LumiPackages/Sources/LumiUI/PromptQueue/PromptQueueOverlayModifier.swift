import LumiKit
import LumiState
import SwiftUI

/// Toggle açıkken terminalin ortasında, kartın %90 genişliğinde bir panel açar;
/// arka planı karartır, dışına tıklama/Escape kapatır. `.popover` yerine in-card
/// overlay: merkezi konum ve geniş textfield için.
///
/// Karartma + kapatma sözleşmesi ortak `ModalOverlay`'dedir (Faz 7.2).
struct PromptQueueOverlayModifier: ViewModifier {
    @Binding var isOpen: Bool
    let terminalID: TerminalID
    var store: PromptQueueStore

    /// Panelin kart içindeki oranları — ölçek dışı geometri sabitleri.
    private enum Metrics {
        static let widthRatio: CGFloat = 0.9
        static let maxWidth: CGFloat = 760
        static let maxHeightRatio: CGFloat = 0.92
        static let entryScale: CGFloat = 0.97
        static let entryDuration: TimeInterval = 0.16
    }

    func body(content: Content) -> some View {
        content.overlay {
            if isOpen {
                GeometryReader { geo in
                    ModalOverlay(onDismiss: { isOpen = false }) {
                        PromptQueuePanel(
                            terminalID: terminalID,
                            store: store,
                            onClose: { isOpen = false }
                        )
                        .frame(width: min(geo.size.width * Metrics.widthRatio, Metrics.maxWidth))
                        .frame(maxHeight: geo.size.height * Metrics.maxHeightRatio)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: Metrics.entryScale)))
            }
        }
        .animation(.easeOut(duration: Metrics.entryDuration), value: isOpen)
    }
}

extension View {
    func promptQueueOverlay(
        isOpen: Binding<Bool>,
        terminalID: TerminalID,
        store: PromptQueueStore
    ) -> some View {
        modifier(PromptQueueOverlayModifier(isOpen: isOpen, terminalID: terminalID, store: store))
    }
}
