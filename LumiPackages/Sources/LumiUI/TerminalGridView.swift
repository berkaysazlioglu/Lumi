import LumiKit
import LumiState
import SwiftUI

/// Aktif repo'nun görünür terminal kartlarını GridLayoutMath frame'leriyle dizer.
/// `fit` viewport'a sığar (scroll yok); `scroll` min boyutu koruyup dikey scroll'lanır.
struct TerminalGridView: View {
    let terminals: [TerminalMeta]
    let layout: LumiKit.GridLayout
    let activeTerminalID: TerminalID?
    /// Feed watchdog'ın donmuş işaretlediği terminaller (design/00 Ek A §A.2-10).
    /// Varsayılan boş: host bağlanana dek rozet çıkmaz.
    var stalledIDs: Set<TerminalID> = []
    let viewProvider: any TerminalViewProviding
    let promptQueue: PromptQueueStore
    let onFocus: (TerminalID) -> Void
    let onMinimize: (TerminalID) -> Void
    let onMaximize: (TerminalID) -> Void
    let onClose: (TerminalID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let frames = GridLayoutMath.frames(
                layout: layout,
                container: geometry.size,
                visibleCount: terminals.count
            )
            if layout.heightMode == .fit {
                placedCards(frames: frames)
            } else {
                ScrollView {
                    placedCards(frames: frames)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: GridLayoutMath.contentHeight(frames: frames),
                            alignment: .topLeading
                        )
                }
            }
        }
    }

    private func placedCards(frames: [CGRect]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(terminals.enumerated()), id: \.element.id) { index, meta in
                if index < frames.count {
                    let frame = frames[index]
                    TerminalCardView(
                        meta: meta,
                        isActive: activeTerminalID == meta.id,
                        isStalled: stalledIDs.contains(meta.id),
                        viewProvider: viewProvider,
                        promptQueue: promptQueue,
                        onFocus: { onFocus(meta.id) },
                        onMinimize: { onMinimize(meta.id) },
                        onMaximize: { onMaximize(meta.id) },
                        onClose: { onClose(meta.id) }
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }
}

/// Terminal kartı: ortak kart çerçevesi (`TerminalCardChrome`) + ortak header
/// (`TerminalCardHeader`) + canlı terminal. Başlık `TerminalMeta.displayTitle`.
struct TerminalCardView: View {
    let meta: TerminalMeta
    let isActive: Bool
    var isStalled = false
    let viewProvider: any TerminalViewProviding
    let promptQueue: PromptQueueStore
    let onFocus: () -> Void
    let onMinimize: () -> Void
    let onMaximize: () -> Void
    let onClose: () -> Void

    @State private var isQueueOpen = false

    var body: some View {
        TerminalCardChrome(
            isActive: isActive,
            terminalID: meta.id,
            promptQueue: promptQueue,
            isQueueOpen: $isQueueOpen
        ) {
            TerminalCardHeader(
                meta: meta,
                isActive: isActive,
                isStalled: isStalled,
                style: .grid,
                promptQueue: promptQueue,
                isQueueOpen: $isQueueOpen,
                zoomIcon: "arrow.up.left.and.arrow.down.right",
                onZoom: onMaximize,
                onMinimize: onMinimize,
                onClose: onClose,
                onTap: onFocus
            )
        } content: {
            TerminalHostView(terminalID: meta.id, provider: viewProvider)
                .id(meta.id)
                .padding(8)
        }
    }
}
