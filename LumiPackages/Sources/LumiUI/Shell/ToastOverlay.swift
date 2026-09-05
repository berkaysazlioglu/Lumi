import LumiKit
import LumiState
import SwiftUI

/// Sağ-alt toast yığını (tip rengiyle sol stripe, max 5, 5sn).
/// Bell toast'una tıklama terminali (minimize ise restore edip) odaklar.
/// Tam görsel parite (blur, progress bar, animasyon parametreleri) Faz 6'da.
public struct ToastOverlay: View {
    private let store: ToastStore
    private let onTerminalTap: (TerminalID) -> Void

    public init(store: ToastStore, onTerminalTap: @escaping (TerminalID) -> Void = { _ in }) {
        self.store = store
        self.onTerminalTap = onTerminalTap
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            ForEach(store.toasts) { toast in
                toastCard(toast)
            }
        }
        .padding(Theme.Spacing.xl)
        .animation(Theme.Motion.standardOut, value: store.toasts)
    }

    private func toastCard(_ toast: ToastStore.Toast) -> some View {
        Panel(variant: .floating) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(stripeColor(for: toast.kind))
                    .frame(width: 3) // ölçek dışı ara değer (v1 stripe genişliği)
                    .accessibilityHidden(true)
                body(for: toast)
                Spacer(minLength: 0)
                IconButton(
                    systemName: "xmark",
                    label: "Dismiss notification",
                    size: .micro,
                    side: nil,
                    showsHoverBackground: false
                ) {
                    store.dismiss(toast.id)
                }
                // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
                .padding(.trailing, 10)
            }
        }
        .frame(minWidth: 280, maxWidth: 360, alignment: .leading)
        // Dikeyde içerik yüksekliğine sabitle: stripe Rectangle açgözlüdür,
        // bu olmadan kart overlay'in önerdiği TÜM pencere yüksekliğine uzuyordu.
        .fixedSize(horizontal: false, vertical: true)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    /// Bir terminale bağlı toast tıklanabilir bir butondur; bilgi toast'ı düz
    /// metindir (Faz 7.6 — `onTapGesture` yerine gerçek buton).
    @ViewBuilder
    private func body(for toast: ToastStore.Toast) -> some View {
        if let terminalID = toast.terminalID {
            Button {
                onTerminalTap(terminalID)
                store.dismiss(toast.id)
            } label: {
                text(for: toast).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(toast.title). \(toast.message)")
            .accessibilityHint("Focuses the terminal")
        } else {
            text(for: toast)
        }
    }

    private func text(for toast: ToastStore.Toast) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(toast.title)
                .font(Theme.Typography.mono(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if !toast.message.isEmpty {
                Text(toast.message)
                    .font(Theme.Typography.mono(.label))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
            }
        }
        // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
        .padding(.horizontal, 10)
        .padding(.vertical, Theme.Spacing.md)
    }

    private func stripeColor(for kind: ToastStore.Toast.Kind) -> Color {
        switch kind {
        case .bell: return Theme.accentVivid
        case .error: return Theme.error
        case .success: return Theme.success
        case .info: return Theme.accentPrimary
        }
    }
}

#if DEBUG
#Preview("ToastOverlay") {
    let store = ToastStore(autoDismissAfter: .infinity)
    store.show(.error, title: "Commit failed", message: "nothing added to commit")
    store.show(.bell, title: "Terminal 2", message: "waiting for input", terminalID: TerminalID())
    return ToastOverlay(store: store)
        .frame(width: 480, height: 240, alignment: .bottomTrailing)
        .background(Theme.bgDeep)
}
#endif
