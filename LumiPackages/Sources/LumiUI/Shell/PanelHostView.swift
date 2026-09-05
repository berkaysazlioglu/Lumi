import LumiKit
import SwiftUI

/// Bir panel yuvasının çizimi (Faz 6.2).
///
/// Yuvanın öğeleri `PanelItemRegistry`'den çözülür, 1px ayraçla dikey dizilir
/// ve genişlik `PanelLayout`'tan gelir. Yuva gizliyse ya da çizilecek öğe
/// kalmadıysa (hepsi `isAvailable == false`) hiçbir şey çizilmez — böylece
/// "repo yokken sidebar da yok" davranışı yapısal olarak gelir.
struct PanelHostView: View {
    /// Yuva nasıl çiziliyor: kabuğun HStack'inde sabit (orta alanı daraltır)
    /// mı, kenar hover'ıyla içeriğin ÜSTÜNDE geçici mi (karar 44).
    enum Presentation {
        case docked
        case revealed
    }

    let slot: PanelSlot
    let registry: PanelItemRegistry
    var presentation: Presentation = .docked

    @Shell private var shell

    /// Overlay yuvasının içerikten ayrılan gölgesi.
    private static let revealShadowRadius: CGFloat = 18
    private static let revealShadowOpacity = 0.45

    var body: some View {
        let items = resolvedItems
        if !items.isEmpty {
            HStack(spacing: 0) {
                if slot == .right { edgeDivider }
                stack(items)
                if slot == .left { edgeDivider }
            }
            .shadow(
                color: presentation == .revealed
                    ? .black.opacity(Self.revealShadowOpacity) : .clear,
                radius: presentation == .revealed ? Self.revealShadowRadius : 0
            )
        }
    }

    private func stack(_ items: [PanelItemDescriptor]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
                }
                itemView(item)
            }
        }
        // Yan yuvalar sabit genişliktedir; `.bottom` (henüz kayıtlı öğesi yok)
        // kalan genişliği alır.
        .frame(width: slot == .bottom ? nil : shell.layout.width(for: slot))
        .background(Theme.bgSurface)
    }

    /// Yuvayı orta alandan ayıran 1px çizgi (eski `RootView.mainArea` ayraçları).
    private var edgeDivider: some View {
        Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
    }

    private var resolvedItems: [PanelItemDescriptor] {
        switch presentation {
        case .docked:
            guard shell.layout.isSlotVisible(slot) else { return [] }
        case .revealed:
            // Overlay yaşam döngüsünü parent yönetir. Kapanış transition'ı
            // bitmeden içeriği boşaltmak kayma animasyonunu keser.
            break
        }
        return registry.resolved(slot: slot, layout: shell.layout.panelLayout, context: shell)
    }

    @ViewBuilder
    private func itemView(_ item: PanelItemDescriptor) -> some View {
        switch item.sizing {
        case .fit:
            item.makeView()
        case .fill:
            item.makeView().frame(maxHeight: .infinity)
        }
    }
}
