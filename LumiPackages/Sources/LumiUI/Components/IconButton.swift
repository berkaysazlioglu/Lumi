import SwiftUI

/// İkonu-tek buton — modülün TEK ikon butonu (Faz 7.2 / 7.6).
///
/// `label` **zorunludur** ve doğrudan `accessibilityLabel`'a bağlanır: ikonun
/// kendisi VoiceOver için anlamsız olduğundan, etiketsiz bir ikon butonu
/// kurmak API düzeyinde mümkün değildir (etiketin boş olmadığı
/// `IconButtonLabel` + `IconButtonLabelTests` ile doğrulanır). Aynı metin
/// `.help()` ipucu olarak da kullanılır.
///
/// Hover durumu içeridedir — çağrı yerlerinde `@State private var isHovering`
/// kopyası kalmaz.
struct IconButton: View {
    /// Butonun anlamı: renk ailesini seçer.
    enum Role {
        /// Sessiz ikon; hover'da aydınlanır.
        case standard
        /// Yıkıcı eylem (kapat/sil); hover'da kırmızıya döner.
        case destructive
        /// Açık/kapalı durumu olan toggle; aktifken accent.
        case toggle
    }

    let systemName: String
    /// Erişilebilirlik etiketi — boş olamaz.
    let label: String
    var size: Theme.Typography.Size = .label
    var weight: Font.Weight = .bold
    /// Kare tıklama alanının kenarı; `nil` ise ikon kendi boyutunda kalır.
    var side: CGFloat? = 20
    var cornerRadius: CGFloat = Theme.Radius.sm
    var role: Role = .standard
    /// `.toggle` rolünde açık/kapalı durumu.
    var isActive = false
    /// Bazı satır içi butonlarda (toast kapatma) zemin istenmez.
    var showsHoverBackground = true
    let action: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: action) {
                Image(systemName: systemName)
                    .font(Theme.Typography.ui(size, weight: weight))
                    .foregroundStyle(foreground(isHovering: isHovering))
                    .frame(width: side, height: side)
                    .background(background(isHovering: isHovering))
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(IconButtonLabel.resolve(label))
        .help(IconButtonLabel.resolve(label))
    }

    private func foreground(isHovering: Bool) -> Color {
        switch role {
        case .standard:
            return isHovering ? Theme.textPrimary : Theme.textMuted
        case .destructive:
            return isHovering ? Theme.error : Theme.textMuted
        case .toggle:
            if isActive { return Theme.accentPrimary }
            return isHovering ? Theme.textPrimary : Theme.textSecondary
        }
    }

    private func background(isHovering: Bool) -> Color {
        guard showsHoverBackground else { return .clear }
        switch role {
        case .standard:
            return isHovering ? Theme.bgElevated : .clear
        case .destructive:
            return isHovering ? Theme.error.opacity(0.2) : .clear
        case .toggle:
            return isActive || isHovering ? Theme.bgElevated : .clear
        }
    }
}

/// `IconButton.label`'ın boş olamayacağı kuralının saf hâli.
///
/// Kural view'ın içinde bir `precondition` olarak yaşasaydı yalnız çalışma
/// zamanında patlardı; burada saf bir fonksiyon olduğu için test edilebilir ve
/// `IconButtonAccessibilityTests` tüm çağrı yerlerini kaynak üzerinden tarar.
enum IconButtonLabel {
    /// Boşluk-dışı en az bir karakter içeriyor mu?
    static func isValid(_ raw: String) -> Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Geçerli etiketi kırpılmış hâliyle döndürür; geçersizse görünür bir
    /// yer tutucuya düşer (sessizce etiketsiz kalmaktansa fark edilsin).
    static func resolve(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unlabeled button" : trimmed
    }
}

#if DEBUG
#Preview("IconButton") {
    HStack(spacing: Theme.Spacing.lg) {
        IconButton(systemName: "xmark", label: "Close", side: 28, cornerRadius: Theme.Radius.md) {}
        IconButton(systemName: "magnifyingglass", label: "Filter files", weight: .semibold) {}
        IconButton(systemName: "xmark", label: "Close terminal", size: .caption, role: .destructive) {}
        IconButton(
            systemName: "gearshape",
            label: "Settings",
            size: .body,
            weight: .regular,
            side: 26,
            cornerRadius: Theme.Radius.md,
            role: .toggle,
            isActive: true
        ) {}
    }
    .padding(Theme.Spacing.xxl)
    .background(Theme.bgSurface)
}
#endif
