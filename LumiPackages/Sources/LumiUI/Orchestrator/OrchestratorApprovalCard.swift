import LumiKit
import LumiState
import SwiftUI

/// Bekleyen onaylar (karar 114 Faz 3): composer'ın hemen üstünde, sohbetle
/// birlikte kaymaz — kullanıcı "doğru chat'e mi gidiyor?" sorusunu hedef
/// satırından, ne gideceğini gövdeden görür. ⌘↩ ilk kartı onaylar.
struct OrchestratorApprovalList: View {
    let approvals: OrchestratorApprovals

    var body: some View {
        if !approvals.pending.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                ForEach(Array(approvals.pending.enumerated()), id: \.element.id) { index, request in
                    OrchestratorApprovalCard(
                        request: request,
                        isPrimary: index == 0,
                        onApprove: { approvals.approve(request.id) },
                        onReject: { approvals.reject(request.id) }
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.lg)
        }
    }
}

struct OrchestratorApprovalCard: View {
    let request: OrchestratorApprovalRequest
    /// İlk kart klavye kısayollarını alır.
    let isPrimary: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    private static var bodyMaxHeight: CGFloat { Theme.scaled(160) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.Typography.ui(.body, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                Text(request.title)
                    .font(Theme.Typography.mono(.base, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Needs your approval")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.warning)
            }
            Text(request.target)
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
            ScrollView {
                Text(request.body)
                    .font(Theme.Typography.ui(.body))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
            }
            .frame(maxHeight: Self.bodyMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            if let note = request.note {
                Label(note, systemImage: "clock")
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: Theme.Spacing.md) {
                Spacer()
                rejectButton
                approveButton
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.warning.opacity(0.6), lineWidth: Theme.Stroke.hairline)
        )
    }

    private var icon: String {
        switch request.kind {
        case .sendMessage: return "paperplane"
        case .startTerminal: return "plus.rectangle.on.rectangle"
        }
    }

    private var approveTitle: String {
        let verb = request.kind == .sendMessage ? "Send" : "Start"
        return isPrimary ? "\(verb)  ⌘↩" : verb
    }

    @ViewBuilder
    private var approveButton: some View {
        let button = LumiActionButton(title: approveTitle, kind: .primary, action: onApprove)
        if isPrimary {
            button.keyboardShortcut(.return, modifiers: .command)
        } else {
            button
        }
    }

    private var rejectButton: some View {
        LumiActionButton(title: "Reject", kind: .secondary, action: onReject)
    }
}

#if DEBUG
#Preview("Approval card") {
    OrchestratorApprovalCard(
        request: OrchestratorApprovalRequest(
            kind: .sendMessage,
            title: "Send to “api-refactor”",
            target: "api · api-wt · feature/login · claude · working",
            body: "Testleri tekrar koş ve kırılanları düzelt.",
            note: "The agent is busy — the message is queued and sent when it finishes its turn."
        ),
        isPrimary: true, onApprove: {}, onReject: {}
    )
    .padding()
    .frame(width: 720)
    .background(Theme.bgSurface)
}
#endif
