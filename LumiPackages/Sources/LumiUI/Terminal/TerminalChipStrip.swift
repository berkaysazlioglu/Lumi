import LumiKit
import SwiftUI

/// Yatay terminal chip şeridi (refactor 6.7).
///
/// İki çağrı yeri vardı ve ikisi de BİREBİR aynı kodu taşıyordu: minimize
/// şeridi (`TerminalsRouteView`) ve maximize altındaki switcher
/// (`MaximizedTerminalView`). Tek fark, minimize şeridinin başındaki
/// "Minimized:" etiketi — o da opsiyonel parametre oldu.
///
/// Ölçüler değişmedi: 6pt aralık, 5pt köşe, 24pt şerit yüksekliği.
struct TerminalChipStrip: View {
    /// Şeridin başındaki muted etiket (minimize şeridi için "Minimized:").
    var label: String?
    let items: [TerminalMeta]
    let onSelect: (TerminalID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let label {
                    Text(label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
                ForEach(items) { meta in
                    chip(meta)
                }
            }
        }
        .frame(height: 24)
    }

    private func chip(_ meta: TerminalMeta) -> some View {
        Button {
            onSelect(meta.id)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(Theme.statusColor(for: meta.status))
                    .frame(width: 6, height: 6)
                Text(meta.displayTitle)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
    }
}
