import SwiftUI

/// Commit/checkin mesajı alanı (karar 47): çok satırlı metin + sağ altta
/// "Claude ile üret" düğmesi. Git ve Plastic composer'ları aynı bileşeni
/// kullanır; üretim mantığı bileşende değil, `ShellContext` intent'indedir.
///
/// Düğme alanın İÇİNDE durur (overlay), metin sağ altta düğmenin altına
/// girmesin diye alt satıra düğme kadar sağ pay bırakılır. Üretim sürerken
/// düğme yerine küçük ilerleme göstergesi çıkar.
struct CommitMessageField: View {
    let placeholder: String
    @Binding var text: String
    let isGenerating: Bool
    /// En az bir dosya seçili mi? Seçim yoksa düğme kapalıdır.
    let canGenerate: Bool
    let onGenerate: () -> Void

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(3...6)
            .font(Theme.Typography.ui(.body))
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .padding(Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            .overlay(alignment: .bottomTrailing) {
                generateControl
                    .padding(Theme.Spacing.sm)
            }
    }

    @ViewBuilder
    private var generateControl: some View {
        if isGenerating {
            ProgressView()
                .controlSize(.small)
                .frame(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
                .help("Generating message with Claude…")
                .accessibilityLabel("Generating message with Claude")
        } else {
            IconButton(
                systemName: "sparkles",
                label: canGenerate ? "Generate message with Claude" : "Select files to generate a message",
                action: onGenerate
            )
            .disabled(!canGenerate)
            .foregroundStyle(canGenerate ? Theme.textSecondary : Theme.textMuted)
        }
    }
}
