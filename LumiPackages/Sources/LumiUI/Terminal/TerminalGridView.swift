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
    /// Karar bekleyen terminaller (karar 77 vurgusunun ikinci kaynağı).
    var awaitingDecisionIDs: Set<TerminalID> = []
    let viewProvider: any TerminalViewProviding
    let promptQueue: PromptQueueStore
    let onFocus: (TerminalID) -> Void
    let onMinimize: (TerminalID) -> Void
    let onMaximize: (TerminalID) -> Void
    let onClose: (TerminalID) -> Void
    /// Karar 97 Edit modu: kartlar sürüklenip başka kartın üstüne bırakılınca
    /// `onSwap` ile takas edilir; terminal gövdeleri tık almaz.
    var isArranging = false
    var onSwap: (TerminalID, TerminalID) -> Void = { _, _ in }
    var onEndArranging: () -> Void = {}
    /// Klavye odağı Edit modundayken başka bir yere geçti (⌘1–9, spawn,
    /// bildirim, Projects ajan satırı…): mod odağı geri ÇALMADAN biter — aksi
    /// hâlde tuşlar karartılmış terminale giderdi.
    var onArrangeFocusLost: () -> Void = {}

    /// `@GestureState`: jest iptal edilince ya da kart sürükleme sırasında
    /// kaldırılınca kendiliğinden sıfırlanır — bayat drop-target vurgusu kalmaz.
    @GestureState private var drag: ArrangeDrag?
    @FocusState private var isArrangeFocused: Bool

    private static let coordinateSpace = "terminalGrid"

    var body: some View {
        grid
            .focusable(isArranging)
            .focused($isArrangeFocused)
            .focusEffectDisabled()
            // Edit modunda klavye odağı terminalden alınır: Esc PTY'ye değil
            // moddan çıkışa gider.
            .onKeyPress(.escape) {
                guard isArranging else { return .ignored }
                onEndArranging()
                return .handled
            }
            .onChange(of: isArranging, initial: true) { _, arranging in
                isArrangeFocused = arranging
            }
            .onChange(of: isArrangeFocused) { wasFocused, isFocused in
                if wasFocused, !isFocused, isArranging { onArrangeFocusLost() }
            }
    }

    private var grid: some View {
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
                    let isAwaitingDecision = awaitingDecisionIDs.contains(meta.id)
                    let isDragged = drag?.id == meta.id
                    TerminalCardView(
                        meta: meta,
                        isActive: activeTerminalID == meta.id,
                        isStalled: stalledIDs.contains(meta.id),
                        isAwaitingDecision: isAwaitingDecision,
                        needsAttention: TerminalAttention.isNeeded(
                            status: meta.status,
                            isAwaitingDecision: isAwaitingDecision,
                            isSelected: activeTerminalID == meta.id
                        ),
                        viewProvider: viewProvider,
                        promptQueue: promptQueue,
                        onFocus: { onFocus(meta.id) },
                        onMinimize: { onMinimize(meta.id) },
                        onMaximize: { onMaximize(meta.id) },
                        onClose: { onClose(meta.id) },
                        arrangement: isArranging
                            ? .init(position: index + 1, isDropTarget: dropTargetID(frames: frames) == meta.id)
                            : nil
                    )
                    .frame(width: frame.width, height: frame.height)
                    .scaleEffect(isDragged ? ArrangeDrag.liftScale : 1)
                    .offset(x: frame.minX, y: frame.minY)
                    .offset(isDragged ? drag?.translation ?? .zero : .zero)
                    .zIndex(isDragged ? 1 : 0)
                    .gesture(arrangeGesture(for: meta.id, frames: frames), including: isArranging ? .all : .subviews)
                }
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        // Yalnız Edit modunda: spawn/close/minimize'da animasyonlu frame, kare
        // başına terminal resize'ı (SIGWINCH) ve TUI titremesi demekti.
        .animation(isArranging ? Theme.Motion.standardEase : nil, value: terminals.map(\.id))
    }

    // MARK: - Edit modu (karar 97)

    private func arrangeGesture(for id: TerminalID, frames: [CGRect]) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.coordinateSpace))
            .updating($drag) { value, state, _ in
                state = ArrangeDrag(id: id, translation: value.translation, location: value.location)
            }
            .onEnded { value in
                if let target = targetID(at: value.location, dragged: id, frames: frames) {
                    onSwap(id, target)
                }
            }
    }

    /// Süren sürüklemede imlecin üstünde durduğu kart.
    private func dropTargetID(frames: [CGRect]) -> TerminalID? {
        guard let drag else { return nil }
        return targetID(at: drag.location, dragged: drag.id, frames: frames)
    }

    /// Noktadaki (sürüklenenden farklı) kart.
    private func targetID(at location: CGPoint, dragged: TerminalID, frames: [CGRect]) -> TerminalID? {
        ArrangeDrag.targetIndex(at: location, frames: frames)
            .flatMap { terminals.indices.contains($0) ? terminals[$0].id : nil }
            .flatMap { $0 == dragged ? nil : $0 }
    }
}

/// Edit modunda süren tek sürükleme (karar 97).
struct ArrangeDrag: Equatable {
    /// Tutulan kartın hafifçe büyümesi — "elde" olduğunu gösterir.
    static let liftScale: CGFloat = 1.03

    let id: TerminalID
    let translation: CGSize
    /// Grid koordinatında imleç — bırakma hedefi buradan çözülür.
    let location: CGPoint

    /// Noktayı içeren kartın indeksi; boşluğa bırakılırsa nil (takas yok).
    static func targetIndex(at location: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(location) }
    }
}

/// Terminal kartı: ortak kart çerçevesi (`TerminalCardChrome`) + ortak header
/// (`TerminalCardHeader`) + canlı terminal. Başlık `TerminalMeta.displayTitle`.
struct TerminalCardView: View {
    let meta: TerminalMeta
    let isActive: Bool
    var isStalled = false
    var isAwaitingDecision = false
    var needsAttention = false
    let viewProvider: any TerminalViewProviding
    let promptQueue: PromptQueueStore
    let onFocus: () -> Void
    let onMinimize: () -> Void
    let onMaximize: () -> Void
    let onClose: () -> Void
    /// Karar 97: Edit modundaysa kartın sıra bilgisi; normal modda nil.
    var arrangement: Arrangement?

    struct Arrangement: Equatable {
        /// Görünür sıradaki yeri (1 tabanlı) — ⌘ indeksinin karşılığı.
        let position: Int
        /// Sürüklenen kart şu an bunun üstünde: bırakılırsa takas olur.
        let isDropTarget: Bool
    }

    @State private var isQueueOpen = false

    var body: some View {
        TerminalCardChrome(
            isActive: isActive || arrangement?.isDropTarget == true,
            needsAttention: needsAttention,
            terminalID: meta.id,
            promptQueue: promptQueue,
            isQueueOpen: $isQueueOpen
        ) {
            TerminalCardHeader(
                meta: meta,
                isActive: isActive,
                isStalled: isStalled,
                isAwaitingDecision: isAwaitingDecision,
                needsAttention: needsAttention,
                style: .grid,
                promptQueue: promptQueue,
                isQueueOpen: $isQueueOpen,
                zoomIcon: "arrow.up.left.and.arrow.down.right",
                zoomLabel: "Maximize \(meta.displayTitle)",
                onZoom: onMaximize,
                onMinimize: onMinimize,
                onClose: onClose,
                onTap: onFocus,
                isArranging: arrangement != nil
            )
        } content: {
            TerminalHostView(terminalID: meta.id, provider: viewProvider)
                .id(meta.id)
                .padding(Theme.Spacing.md)
                .allowsHitTesting(arrangement == nil)
                .overlay {
                    if let arrangement {
                        ArrangeCardOverlay(position: arrangement.position)
                    }
                }
        }
    }
}

/// Edit modunda terminal gövdesinin üstü: karartma + sıra rozeti + tutamaç.
/// Overlay hit-test'i terminale geçirmez — sürükleme kartın her yerinden başlar.
private struct ArrangeCardOverlay: View {
    /// Terminal içeriği tanınacak kadar görünür kalsın, rozet öne çıksın.
    static let dimOpacity = 0.55

    let position: Int

    var body: some View {
        ZStack {
            Theme.bgDeep.opacity(Self.dimOpacity)
            VStack(spacing: Theme.Spacing.sm) {
                Text("\(position)")
                    .font(Theme.Typography.mono(.display, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(Theme.textMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Position \(position). Drag onto another terminal to swap.")
        }
        .contentShape(Rectangle())
    }
}
