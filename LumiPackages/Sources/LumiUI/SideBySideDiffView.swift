import LumiKit
import SwiftUI

/// İki kolonlu (side-by-side) diff render'ı (karar 4 revize): sol = eski, sağ =
/// yeni; ekleme yeşil, silme kırmızı, context nötr, karşılıksız satır filler.
/// LazyVStack ile sanallaştırılır; uzun satırlar sarar (satır hizası korunur).
struct SideBySideDiffView: View {
    let diff: UnifiedDiff
    var fontSize: CGFloat = 12

    private static let gutterWidth: CGFloat = 44

    var body: some View {
        let model = SideBySideDiffBuilder.build(diff)
        Group {
            if model.isBinary {
                placeholder("(binary file)")
            } else if model.rows.isEmpty {
                placeholder("(no changes)")
            } else {
                ScrollView([.vertical]) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                            rowView(row)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgSurface)
    }

    @ViewBuilder
    private func rowView(_ row: SideBySideDiffBuilder.Row) -> some View {
        switch row {
        case .header(let text):
            Text(text)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(Theme.accentCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.bgElevated)
        case .lines(let left, let right):
            HStack(alignment: .top, spacing: 0) {
                cellView(left)
                Rectangle().fill(Theme.border).frame(width: 1)
                cellView(right)
            }
        }
    }

    private func cellView(_ cell: SideBySideDiffBuilder.Cell?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(cell?.lineNumber.map(String.init) ?? "")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .frame(width: Self.gutterWidth, alignment: .trailing)
            Text(cell?.text ?? "")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(textColor(cell))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(cell))
    }

    private func textColor(_ cell: SideBySideDiffBuilder.Cell?) -> Color {
        guard let cell else { return Theme.textMuted }
        switch cell.kind {
        case .context: return Theme.textPrimary
        case .addition: return Theme.success
        case .deletion: return Theme.error
        }
    }

    private func background(_ cell: SideBySideDiffBuilder.Cell?) -> Color {
        guard let cell else { return Theme.bgDeep } // filler (karşılıksız satır)
        switch cell.kind {
        case .context: return .clear
        case .addition: return Theme.success.opacity(0.13)
        case .deletion: return Theme.error.opacity(0.13)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
