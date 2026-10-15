import SwiftUI

/// Lumi'nin kendi onay dialogu (karar 118) — native `confirmationDialog`'un
/// yerine: koyu panel, mono yazı, `LumiActionButton`'lar.
///
/// Butonlar sağa dizilir, en sağdaki birincildir (macOS düzeni). İptal
/// dışarı tıklama ve Escape'le de çalışır (`ModalOverlay`); birincil eylem
/// Return'e bağlıdır.
struct ConfirmDialog: View {
    struct Action: Identifiable {
        let title: String
        var kind: LumiActionButton.Kind = .secondary
        let perform: () -> Void

        var id: String { title }
    }

    let icon: String
    var iconColor: Color = Theme.accentPrimary
    let title: String
    let message: String
    var note: String?
    let cancel: Action
    /// Soldan sağa; sonuncusu birincil (Return).
    let actions: [Action]

    private static var width: CGFloat { Theme.scaled(460) }
    private static var iconSide: CGFloat { Theme.scaled(32) }
    private static let iconBackgroundOpacity = 0.15

    var body: some View {
        ModalOverlay(onDismiss: cancel.perform) {
            Panel(variant: .modal) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    buttons
                }
                .padding(Theme.Spacing.xxl)
                .frame(width: Self.width, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            Image(systemName: icon)
                .font(Theme.Typography.ui(.body, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: Self.iconSide, height: Self.iconSide)
                .background(Circle().fill(iconColor.opacity(Self.iconBackgroundOpacity)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(title)
                    .font(Theme.Typography.titleMono)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: 0)
            LumiActionButton(title: cancel.title, kind: cancel.kind, action: cancel.perform)
                .keyboardShortcut(.cancelAction)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index == actions.count - 1 {
                    LumiActionButton(title: action.title, kind: action.kind, action: action.perform)
                        .keyboardShortcut(.defaultAction)
                } else {
                    LumiActionButton(title: action.title, kind: action.kind, action: action.perform)
                }
            }
        }
    }
}

#if DEBUG
#Preview("ConfirmDialog") {
    ConfirmDialog(
        icon: "arrow.down.circle",
        title: "Restart Lumi to install 0.8.7?",
        message: "Lumi will quit, install the update and reopen.",
        note: "Choose Install on Quit to keep working.",
        cancel: .init(title: "Cancel") {},
        actions: [
            .init(title: "Install on Quit") {},
            .init(title: "Restart Now", kind: .destructive) {},
        ]
    )
    .frame(width: 720, height: 420)
    .background(Theme.bgDeep)
}
#endif
