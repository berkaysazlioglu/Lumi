import LumiKit
import SwiftUI

/// Sade grid ayar popover'ı (design/03 — iki eksenli model): tetik butonu mevcut
/// yerleşimi özetler, popover'da iki segmented kontrol — Kolon (Auto·1–5) ve
/// Yükseklik (Sığdır·Kaydır). Header ve FocusModeBar ortak kullanır (DRY).
struct GridSettingsControl: View {
    let layout: LumiKit.GridLayout
    let onChange: (LumiKit.GridLayout) -> Void

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11))
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Theme.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            popoverBody
        }
    }

    private var summary: String {
        let columns = layout.mode == .auto ? "Auto" : "\(layout.count) Kolon"
        let height = layout.heightMode == .fit ? "Sığdır" : "Kaydır"
        return "\(columns) · \(height)"
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(title: "Kolon") {
                SegmentedRow(
                    options: GridColumnOption.allOptions,
                    isSelected: { $0.matches(layout) },
                    label: { $0.label },
                    onSelect: { onChange($0.apply(to: layout)) }
                )
            }
            section(title: "Yükseklik") {
                SegmentedRow(
                    options: [LumiKit.GridLayout.HeightMode.fit, .scroll],
                    isSelected: { $0 == layout.heightMode },
                    label: { $0 == .fit ? "Sığdır" : "Kaydır" },
                    onSelect: { var copy = layout; copy.heightMode = $0; onChange(copy) }
                )
            }
            if layout.heightMode == .scroll {
                section(title: "Satır oranı (genişliğe göre)") {
                    SegmentedRow(
                        options: LumiKit.GridLayout.HeightRatio.allCases,
                        isSelected: { $0 == layout.heightRatio },
                        label: { $0.label },
                        onSelect: { var copy = layout; copy.heightRatio = $0; onChange(copy) }
                    )
                }
            }
            Text(layout.heightMode == .fit
                 ? "Tüm terminaller pencereye sığar (scroll yok)."
                 : "Terminal min yüksekliği = genişlik × oran; taşınca dikey scroll.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 280)
        .background(Theme.bgSurface)
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}

/// Kolon ekseni seçenekleri: Auto + sabit 1–5. LumiKit.GridLayout'a iki-yönlü eşlenir.
private enum GridColumnOption: Hashable {
    case auto
    case fixed(Int)

    static let allOptions: [GridColumnOption] = [.auto, .fixed(1), .fixed(2), .fixed(3), .fixed(4), .fixed(5)]

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .fixed(let n): return "\(n)"
        }
    }

    func matches(_ layout: LumiKit.GridLayout) -> Bool {
        switch self {
        case .auto: return layout.mode == .auto
        case .fixed(let n): return layout.mode == .columns && layout.count == n
        }
    }

    func apply(to layout: LumiKit.GridLayout) -> LumiKit.GridLayout {
        switch self {
        case .auto: return LumiKit.GridLayout(mode: .auto, count: layout.count, heightMode: layout.heightMode)
        case .fixed(let n): return LumiKit.GridLayout(mode: .columns, count: n, heightMode: layout.heightMode)
        }
    }
}

/// Tema uyumlu küçük segmented kontrol (native picker yerine — sade/polished).
private struct SegmentedRow<Option>: View {
    let options: [Option]
    let isSelected: (Option) -> Bool
    let label: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = isSelected(option)
                Button {
                    onSelect(option)
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(selected ? Theme.accentVivid : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
