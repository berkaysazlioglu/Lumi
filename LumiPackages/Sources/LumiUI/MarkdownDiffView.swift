import LumiKit
import SwiftUI

/// Markdown dosyaları için render'lı görünüm/diff (karar 21): tek kolon unified
/// akış; blok stilleri (başlık, liste, alıntı, kod, tablo, ayraç) görsel olarak
/// render edilir, satır-içi markdown çözülür. Ekleme/silme gutter işareti +
/// zemin rengiyle ayrılır — diff okunabilirliği kaybolmaz.
struct MarkdownDiffView: View {
    let model: MarkdownDiffBuilder.Model
    var fontSize: CGFloat = 13

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
                    .padding(.bottom, 12)
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
                .font(.system(size: fontSize - 1, design: .monospaced))
                .foregroundStyle(Theme.accentCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.bgElevated)
        case .line(let line):
            HStack(alignment: .top, spacing: 8) {
                Text(gutterLabel(line))
                    .font(.system(size: fontSize - 2, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: Self.gutterWidth, alignment: .trailing)
                Rectangle()
                    .fill(markerColor(line.kind))
                    .frame(width: 2)
                lineContent(line)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.trailing, 12)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(line.kind))
        }
    }

    // MARK: - Blok render'ı

    @ViewBuilder
    private func lineContent(_ line: MarkdownDiffBuilder.Line) -> some View {
        switch line.style {
        case .heading(let level):
            Text(styledInline(line.content))
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(level <= 2 ? Theme.accentPrimary : Theme.textPrimary)
                .padding(.top, level <= 2 ? 6 : 3)
        case .bullet(let indent):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Theme.accentCyan)
                prose(line.content)
            }
            .padding(.leading, CGFloat(indent) * Self.indentStep)
        case .ordered(let indent, let marker):
            HStack(alignment: .top, spacing: 6) {
                Text(marker)
                    .font(.system(size: fontSize - 1, design: .monospaced))
                    .foregroundStyle(Theme.accentCyan)
                prose(line.content)
            }
            .padding(.leading, CGFloat(indent) * Self.indentStep)
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Theme.accentPrimary.opacity(0.6))
                    .frame(width: 2)
                prose(line.content)
                    .italic()
                    .foregroundStyle(Theme.textSecondary)
            }
        case .code:
            Text(line.content.isEmpty ? " " : line.content)
                .font(.system(size: fontSize - 1, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.bgDeep)
        case .fence:
            Text(fenceLabel(line.content))
                .font(.system(size: fontSize - 3, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 6)
        case .rule:
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.vertical, 5)
        case .table:
            Text(line.content)
                .font(.system(size: fontSize - 1, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        case .paragraph:
            prose(line.content)
        case .blank:
            Color.clear.frame(height: 5)
        }
    }

    private func prose(_ text: String) -> Text {
        Text(styledInline(text))
            .font(.system(size: fontSize))
            .foregroundColor(Theme.textPrimary)
    }

    /// ```` ```swift ```` → "swift"; dilsiz fence'te sadece işaret gösterilir.
    private func fenceLabel(_ content: String) -> String {
        let language = content.drop { $0 == "`" || $0 == "~" }
            .trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? "···" : language.lowercased()
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 7
        case 2: return fontSize + 4
        case 3: return fontSize + 2
        default: return fontSize + 1
        }
    }

    private func styledInline(_ text: String) -> AttributedString {
        MarkdownInlineStyler.styled(text, fontSize: fontSize)
    }

    // MARK: - Diff işaretleri

    /// "12 +" / "9 −" / "12" — sağa yaslı; numarası olmayan taraf boş kalır.
    private func gutterLabel(_ line: MarkdownDiffBuilder.Line) -> String {
        let number = (line.newLineNumber ?? line.oldLineNumber).map(String.init) ?? ""
        switch line.kind {
        case .addition: return "\(number) +"
        case .deletion: return "\(number) −"
        case .context: return number
        }
    }

    private func markerColor(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Theme.success
        case .deletion: return Theme.error
        case .context: return .clear
        }
    }

    private func background(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .addition: return Theme.success.opacity(0.13)
        case .deletion: return Theme.error.opacity(0.13)
        case .context: return .clear
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
