import LumiKit
import LumiState
import SwiftUI

/// Maximize/solo görünümü (design/03 — tek terminalle rahat çalışma): seçili
/// terminal tüm içerik alanını kaplar; diğer görünür terminaller altta chip
/// şeridine iner. Chip → o terminale geç; restore butonu/Esc → grid'e dön.
///
/// Kart çerçevesi, header'ı ve chip şeridi grid görünümüyle PAYLAŞILIR
/// (`TerminalCardChrome` / `TerminalCardHeader` / `TerminalChipStrip`).
struct MaximizedTerminalView: View {
    let maximized: TerminalMeta
    let others: [TerminalMeta]
    /// Feed watchdog donma sinyali (design/00 Ek A §A.2-10); varsayılan kapalı.
    var isStalled = false
    var isAwaitingDecision = false
    var needsAttention = false
    let viewProvider: any TerminalViewProviding
    let promptQueue: PromptQueueStore
    let onSwitch: (TerminalID) -> Void
    let onMinimize: (TerminalID) -> Void
    let onClose: (TerminalID) -> Void
    let onRestore: () -> Void

    @State private var isQueueOpen = false

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            terminalCard
            if !others.isEmpty {
                TerminalChipStrip(items: others, onSelect: onSwitch)
            }
        }
        // Esc → grid'e dön (macOS exit-command)
        .onExitCommand(perform: onRestore)
    }

    private var terminalCard: some View {
        TerminalCardChrome(
            // Maximize edilen kart her zaman "aktif" çerçeveyi taşır.
            isActive: true,
            needsAttention: needsAttention,
            terminalID: maximized.id,
            promptQueue: promptQueue,
            isQueueOpen: $isQueueOpen
        ) {
            TerminalCardHeader(
                meta: maximized,
                isActive: true,
                isStalled: isStalled,
                isAwaitingDecision: isAwaitingDecision,
                needsAttention: needsAttention,
                style: .maximized,
                promptQueue: promptQueue,
                isQueueOpen: $isQueueOpen,
                // Geri-küçült (maximize'ı kapatır)
                zoomIcon: "arrow.down.right.and.arrow.up.left",
                zoomLabel: "Restore \(maximized.displayTitle)",
                onZoom: onRestore,
                onMinimize: { onMinimize(maximized.id) },
                onClose: { onClose(maximized.id) }
            )
        } content: {
            TerminalHostView(terminalID: maximized.id, provider: viewProvider)
                .id(maximized.id)
                .padding(Theme.Spacing.md)
                .overlay(alignment: .topTrailing) {
                    TerminalSearchOverlay(terminalID: maximized.id)
                }
        }
    }
}
