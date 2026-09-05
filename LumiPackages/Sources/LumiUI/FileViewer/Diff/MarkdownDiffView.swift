import LumiKit
import SwiftUI

/// Markdown dosyaları için render'lı görünüm/diff (karar 21): tek kolon unified
/// akış; blok stilleri (başlık, liste, alıntı, kod, tablo, ayraç) görsel olarak
/// render edilir, satır-içi markdown çözülür. Ekleme/silme gutter işareti +
/// zemin rengiyle ayrılır — diff okunabilirliği kaybolmaz.
struct MarkdownDiffView: View {
    let model: MarkdownDiffBuilder.Model
    /// Gövde puntosu; türev puntolar (`gutter`, `code`, `fence`, başlıklar)
    /// eski `fontSize ± n` aritmetiği yerine ölçek basamağıyla türer (Faz 7.1).
    var size: Theme.Typography.Size = .base

    private static let gutterWidth: CGFloat = 52
    private static let indentStep: CGFloat = 14

    var body: some View {
        Group {
            if model.isBinary {
                placeholder("(binary file)")
            } else if model.rows.isEmpty {
                placeholder("(no changes)")
            } else {
                ScrollView([.vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                            rowView(row)
                        }
                    }
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgSurface)
    }

    @ViewBuilder
    private func rowView(_ row: MarkdownDiffBuilder.Row) -> some View {
        switch row {
        case .hunk(let header):
            Text(header)
                .font(Theme.Typography.mono(size.stepped(-1)))
                .foregroundStyle(Theme.accentCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 3)
                .background(Theme.bgElevated)
        case .line(let line):
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Text(MarkdownRowFormatting.gutterLabel(line))
                    .font(Theme.Typography.mono(size.stepped(-2)))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: Self.gutterWidth, alignment: .trailing)
                Rectangle()
                    .fill(markerColor(line.kind))
                    .frame(width: 2)
                lineContent(line)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.trailing, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.diffBackground(for: line.kind))
        }
    }

    // MARK: - Blok render'ı

    @ViewBuilder
    private func lineContent(_ line: MarkdownDiffBuilder.Line) -> some View {
        switch line.style {
        case .heading(let level):
            Text(styledInline(line.content))
                .font(Theme.Typography.ui(
                    MarkdownRowFormatting.headingSize(level, base: size),
                    weight: .bold
                ))
                .foregroundStyle(level <= 2 ? Theme.accentPrimary : Theme.textPrimary)
                .padding(.top, level <= 2 ? Theme.Spacing.sm : 3)
        case .bullet(let indent):
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text("•")
                    .font(Theme.Typography.ui(size, weight: .bold))
                    .foregroundStyle(Theme.accentCyan)
                prose(line.content)
            }
            .padding(.leading, CGFloat(indent) * Self.indentStep)
        case .ordered(let indent, let marker):
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text(marker)
                    .font(Theme.Typography.mono(size.stepped(-1)))
                    .foregroundStyle(Theme.accentCyan)
                prose(line.content)
            }
            .padding(.leading, CGFloat(indent) * Self.indentStep)
        case .quote:
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Rectangle()
                    .fill(Theme.accentPrimary.opacity(0.6))
                    .frame(width: 2)
                prose(line.content)
                    .italic()
                    .foregroundStyle(Theme.textSecondary)
            }
        case .code:
            Text(line.content.isEmpty ? " " : line.content)
                .font(Theme.Typography.mono(size.stepped(-1)))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxxs)
                .background(Theme.bgDeep)
        case .fence:
            Text(MarkdownRowFormatting.fenceLabel(line.content))
                .font(Theme.Typography.mono(size.stepped(-3), weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, Theme.Spacing.sm)
        case .rule:
            Rectangle()
                .fill(Theme.border)
                .frame(height: Theme.Stroke.hairline)
                .padding(.vertical, 5)
        case .table:
            Text(line.content)
                .font(Theme.Typography.mono(size.stepped(-1)))
                .foregroundStyle(Theme.textPrimary)
        case .paragraph:
            prose(line.content)
        case .blank:
            Color.clear.frame(height: 5)
        }
    }

    private func prose(_ text: String) -> Text {
        Text(styledInline(text))
            .font(Theme.Typography.ui(size))
            .foregroundColor(Theme.textPrimary)
    }

    private func styledInline(_ text: String) -> AttributedString {
        MarkdownInlineStyler.styled(text, size: size)
    }

    // MARK: - Diff işaretleri

    private func markerColor(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Theme.success
        case .deletion: return Theme.error
        case .context: return .clear
        }
    }

    private func placeholder(_ text: String) -> some View {
        EmptyStatePlaceholder(text, density: .full)
    }
}

/// `MarkdownDiffView` satırlarının SAF biçimlendirme kuralları — view'dan
/// bağımsız oldukları için ayrı bir enum'da durur ve birim testten görünür.
enum MarkdownRowFormatting {
    /// ```` ```swift ```` → "swift"; dilsiz fence'te sadece işaret gösterilir.
    static func fenceLabel(_ content: String) -> String {
        let language = content.drop { $0 == "`" || $0 == "~" }
            .trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? "···" : language.lowercased()
    }

    /// Başlık merdiveni: gövde puntosundan kaç basamak YUKARI çıkılacağı.
    /// Eski hâli `fontSize + 7/4/2/1` aritmetiğiydi; ölçek basamağına
    /// çevrildiğinde 13pt tabanda 20/18/15/13 verir (v1: 20/17/15/14).
    static func headingSize(
        _ level: Int,
        base: Theme.Typography.Size
    ) -> Theme.Typography.Size {
        switch level {
        case 1: return base.stepped(3)
        case 2: return base.stepped(2)
        case 3: return base.stepped(1)
        default: return base
        }
    }

    /// "12 +" / "9 −" / "12" — sağa yaslı; numarası olmayan taraf boş kalır.
    static func gutterLabel(_ line: MarkdownDiffBuilder.Line) -> String {
        let number = (line.newLineNumber ?? line.oldLineNumber).map(String.init) ?? ""
        switch line.kind {
        case .addition: return "\(number) +"
        case .deletion: return "\(number) −"
        case .context: return number
        }
    }
}

#if DEBUG
#Preview("MarkdownDiffView — döküman") {
    MarkdownDiffView(model: MarkdownDiffBuilder.buildDocument(PreviewSamples.markdown))
        .frame(width: 620, height: 460)
}

#Preview("MarkdownDiffView — diff") {
    MarkdownDiffView(model: MarkdownDiffBuilder.build(PreviewSamples.diff(filePath: "README.md")))
        .frame(width: 620, height: 320)
}
#endif
