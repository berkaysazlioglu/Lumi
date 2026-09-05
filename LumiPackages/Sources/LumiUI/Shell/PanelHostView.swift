import LumiKit
import SwiftUI

/// Bir panel yuvasının çizimi (Faz 6.2).
///
/// Yuvanın öğeleri `PanelItemRegistry`'den çözülür, 1px ayraçla dikey dizilir
/// ve genişlik `PanelLayout`'tan gelir. Yuva gizliyse ya da çizilecek öğe
/// kalmadıysa (hepsi `isAvailable == false`) hiçbir şey çizilmez — böylece
/// "repo yokken sidebar da yok" davranışı yapısal olarak gelir.
struct PanelHostView: View {
    let slot: PanelSlot
    let registry: PanelItemRegistry

    @Shell private var shell

    var body: some View {
        let items = resolvedItems
        if !items.isEmpty {
            HStack(spacing: 0) {
                if slot == .right { edgeDivider }
                stack(items)
                if slot == .left { edgeDivider }
            }
        }
    }

    private func stack(_ items: [PanelItemDescriptor]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Theme.border).frame(height: 1)
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
        Rectangle().fill(Theme.border).frame(width: 1)
    }

    private var resolvedItems: [PanelItemDescriptor] {
        guard shell.layout.isSlotVisible(slot) else { return [] }
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
