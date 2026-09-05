import LumiKit
import SwiftUI

/// İki kolonlu (side-by-side) diff render'ı (karar 4 revize): sol = eski, sağ =
/// yeni; ekleme yeşil, silme kırmızı, context nötr, karşılıksız satır filler.
/// LazyVStack ile sanallaştırılır; uzun satırlar sarar (satır hizası korunur).
struct SideBySideDiffView: View {
    let diff: UnifiedDiff
    var size: Theme.Typography.Size = .body

    private static let gutterWidth: CGFloat = 44

    /// Satır modeli her body'de yeniden kurulmasın: diff değişince bir kez
    /// hesaplanır (HighlightedCodeView kalıbı).
    @State private var model: SideBySideDiffBuilder.Model?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgSurface)
        .task(id: diff) {
            model = SideBySideDiffBuilder.build(diff)
        }
    }

    @ViewBuilder
    private func content(_ model: SideBySideDiffBuilder.Model) -> some View {
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

    @ViewBuilder
    private func rowView(_ row: SideBySideDiffBuilder.Row) -> some View {
        switch row {
        case .header(let text):
            Text(text)
                .font(Theme.Typography.mono(size))
                .foregroundStyle(Theme.accentCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 3)
                .background(Theme.bgElevated)
        case .lines(let left, let right):
            HStack(alignment: .top, spacing: 0) {
                cellView(left)
                Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                cellView(right)
            }
        }
    }

    private func cellView(_ cell: SideBySideDiffBuilder.Cell?) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Text(cell?.lineNumber.map(String.init) ?? "")
                .font(Theme.Typography.mono(size))
                .foregroundStyle(Theme.textMuted)
                .frame(width: Self.gutterWidth, alignment: .trailing)
            Text(cell?.text ?? "")
                .font(Theme.Typography.mono(size))
                .foregroundStyle(textColor(cell))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xxxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(cell))
    }

    private func textColor(_ cell: SideBySideDiffBuilder.Cell?) -> Color {
        guard let cell else { return Theme.textMuted }
        return Theme.diffForeground(for: cell.kind)
    }

    private func background(_ cell: SideBySideDiffBuilder.Cell?) -> Color {
        guard let cell else { return Theme.bgDeep } // filler (karşılıksız satır)
        return Theme.diffBackground(for: cell.kind)
    }

    private func placeholder(_ text: String) -> some View {
        EmptyStatePlaceholder(text, density: .full)
    }
}

#if DEBUG
#Preview("SideBySideDiffView") {
    SideBySideDiffView(diff: PreviewSamples.diff())
        .frame(width: 760, height: 320)
}

#Preview("SideBySideDiffView — boş") {
    SideBySideDiffView(diff: UnifiedDiff(filePath: "a.txt", isBinary: false, hunks: []))
        .frame(width: 480, height: 200)
}
#endif
