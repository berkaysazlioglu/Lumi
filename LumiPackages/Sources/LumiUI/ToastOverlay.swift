import LumiState
import SwiftUI

/// Sağ-alt toast yığını (spec/23: tip rengiyle sol stripe, max 5, 5sn).
/// Tam görsel parite (blur, progress bar, animasyon parametreleri) Faz 6'da.
public struct ToastOverlay: View {
    private let store: ToastStore

    public init(store: ToastStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(store.toasts) { toast in
                toastCard(toast)
            }
        }
        .padding(16)
        .animation(.easeOut(duration: 0.2), value: store.toasts)
    }

    private func toastCard(_ toast: ToastStore.Toast) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(stripeColor(for: toast.kind))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                if !toast.message.isEmpty {
                    Text(toast.message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Spacer(minLength: 0)
            Button {
                store.dismiss(toast.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .frame(minWidth: 280, maxWidth: 360, alignment: .leading)
        .background(Theme.bgElevated.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: 1)
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
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
