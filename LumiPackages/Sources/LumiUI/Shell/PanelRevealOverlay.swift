import LumiKit
import SwiftUI

/// Gizli yan yuvaların kenar hover'ıyla içeriğin ÜSTÜNDE açılması (karar 44).
///
/// Sabit (docked) yuva kabuğun HStack'inde orta alanı daraltır; bu overlay ise
/// orta alana DOKUNMAZ: pencerenin sol/sağ kenarındaki görünmez şeride fare
/// gelince 100 ms sonra yuva içeriğin üstüne kayar; fare yuvadan çıkınca
/// beklemeden kapanır. Hover bölgesi animasyondan bağımsızdır; açılışta
/// şerit ile panel arasında tracking devri yapılmaz.
///
/// Header (top bar) örtülmez: overlay kabuğun tamamını kapladığı için üstten
/// `TopBarMetrics.height` + ayraç payı bırakılır.
public struct PanelRevealOverlay: View {
    /// Kenar hover'ı anlamlı olan yuvalar — `.bottom`'ın kenarı yoktur.
    public static let slots: [PanelSlot] = [.left, .right]

    let registry: PanelItemRegistry

    @Shell private var shell

    public init(registry: PanelItemRegistry) {
        self.registry = registry
    }

    public var body: some View {
        ZStack {
            ForEach(Self.slots, id: \.self) { slot in
                if shell.layout.canAutoReveal(slot),
                   !registry.resolved(slot: slot, layout: shell.layout.panelLayout, context: shell).isEmpty {
                    EdgeRevealZone(slot: slot, registry: registry)
                        .frame(maxWidth: .infinity, alignment: Self.alignment(for: slot))
                }
            }
        }
        .padding(.top, shell.layout.isFocusMode ? 0 : TopBarMetrics.height + Theme.Stroke.hairline)
    }

    private static func alignment(for slot: PanelSlot) -> Alignment {
        slot == .right ? .trailing : .leading
    }
}

/// Tek kenarın hover şeridi + açılan yuva.
private struct EdgeRevealZone: View {
    let slot: PanelSlot
    let registry: PanelItemRegistry

    @Shell private var shell

    @State private var pendingTask: Task<Void, Never>?

    /// Görünmez tetikleme şeridinin genişliği.
    private static let triggerWidth: CGFloat = Theme.Spacing.md

    private var edge: Edge { slot == .right ? .trailing : .leading }

    var body: some View {
        let isRevealed = shell.layout.isSlotRevealed(slot)
        let panelWidth = shell.layout.width(for: slot) + Theme.Stroke.hairline

        // Tek, kalıcı tracking bölgesi. Genişliği anında değişir; yalnız
        // overlay içindeki panel animasyon alır, hover sınırı hareket etmez.
        Color.clear
            .frame(width: isRevealed ? panelWidth : Self.triggerWidth)
            .frame(maxHeight: .infinity)
            .overlay(alignment: slot == .right ? .trailing : .leading) {
                ZStack {
                    if isRevealed {
                        PanelHostView(slot: slot, registry: registry, presentation: .revealed)
                            .transition(.move(edge: edge))
                    }
                }
                .frame(width: panelWidth)
                .animation(
                    isRevealed ? Theme.Motion.standardOut : Theme.Motion.quickEase,
                    value: isRevealed
                )
                .allowsHitTesting(isRevealed)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    guard !shell.layout.isSlotRevealed(slot), pendingTask == nil else { return }
                    pendingTask = Task { @MainActor in
                        do {
                            try await Task.sleep(for: Theme.Motion.sidebarRevealDelay)
                        } catch {
                            return
                        }
                        guard !Task.isCancelled else { return }
                        pendingTask = nil
                        shell.layout.setRevealed(slot, true)
                    }
                } else {
                    cancelPending()
                    shell.layout.setRevealed(slot, false)
                }
            }
            .onDisappear {
                cancelPending()
                shell.layout.setRevealed(slot, false)
            }
    }

    private func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}

#if DEBUG
#Preview("PanelRevealOverlay") {
    let shell = ShellContext.preview()
    PanelRevealOverlay(registry: PanelItemRegistry())
        .frame(width: 720, height: 400)
        .background(Theme.bgDeep)
        .environment(\.shell, shell)
        .task {
            shell.layout.setSlotVisible(.left, false)
            shell.layout.setAutoReveal(.left, true)
        }
}
#endif
