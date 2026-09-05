import AppKit
import LumiKit
import SwiftUI

/// Agent History satırı açıldığında görünen detay kartı.
///
/// Eskiden açılan alan yalnız mono session ID + preview'in ikinci kopyası +
/// tek butondu; okunmuyordu. Kart artık Orca'nın oturum detayı düzenini
/// izler: aksiyon çubuğu, ilk istem, son turlar ve çalışma dizini.
struct AgentHistoryDetailCard: View {
    let entry: AgentHistoryEntry
    let onResume: () -> Void
    let onCopyCommand: () -> Void
    let onRevealLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            actionBar
            if let firstPrompt = entry.firstPrompt {
                section("First Prompt") {
                    Text(firstPrompt)
                        .font(Theme.Typography.ui(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !entry.recentTurns.isEmpty {
                section("Latest Turns") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(entry.recentTurns) { turn in AgentHistoryTurnCard(turn: turn) }
                    }
                }
            }
            if let cwd = entry.cwd {
                Text(cwd)
                    .font(Theme.Typography.mono(.caption))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(cwd)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Parçalar

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            action("Resume", icon: "play.fill", isPrimary: true, action: onResume)
                .disabled(entry.resumeCommand == nil)
            action("Copy Command", icon: "doc.on.doc", action: onCopyCommand)
                .disabled(entry.resumeCommand == nil)
            action("View Log", icon: "doc.text.magnifyingglass", action: onRevealLog)
            Spacer(minLength: 0)
        }
    }

    private func action(
        _ title: String, icon: String, isPrimary: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon).accessibilityHidden(true)
                Text(title)
            }
            .font(Theme.Typography.ui(.caption, weight: .medium))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(
            HoverButtonStyle(
                foreground: isPrimary ? .white : Theme.textSecondary,
                hoverForeground: isPrimary ? .white : Theme.textPrimary,
                background: isPrimary ? Theme.accentVivid : Theme.bgDeep,
                hoverBackground: isPrimary ? Theme.accentDeep : Theme.border
            )
        )
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(Theme.Typography.ui(.caption, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textMuted)
            content()
        }
    }
}

/// Tek konuşma turu — rol etiketi + metin; kullanıcı turu accent zeminlidir.
struct AgentHistoryTurnCard: View {
    let turn: AgentHistoryTurn

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(turn.role == .user ? "You" : "Agent")
                .font(Theme.Typography.ui(.caption, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text(turn.text)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(turn.role == .user ? Theme.accentPrimary.opacity(0.08) : Theme.bgDeep)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

/// Oturumun git dalı rozeti.
struct AgentHistoryBranchBadge: View {
    let branch: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "arrow.triangle.branch").accessibilityHidden(true)
            Text(branch).lineLimit(1)
        }
        .font(Theme.Typography.ui(.caption))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxxs)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityLabel("Branch \(branch)")
    }
}

#if DEBUG
#Preview("AgentHistoryDetailCard") {
    AgentHistoryDetailCard(
        entry: AgentHistoryEntry(
            provider: .claude,
            sessionID: "d39c3849",
            title: "Agent History sekmesini okunur yap",
            preview: "Kart eklendi",
            updatedAt: .now,
            cwd: "/Users/dev/wkspaces/Github/Lumi",
            logPath: "/Users/dev/.claude/projects/-Lumi/d39c3849.jsonl",
            gitBranch: "main",
            model: "claude-opus-4-1",
            messageCount: 12,
            firstPrompt: "Agent History sekmesini okunur yap; açılan alanda branch, model ve son turlar görünsün.",
            recentTurns: [
                AgentHistoryTurn(role: .user, text: "Kartın zemini olsun"),
                AgentHistoryTurn(role: .assistant, text: "Kart zemini ve kenarlığı eklendi."),
            ]
        ),
        onResume: {}, onCopyCommand: {}, onRevealLog: {}
    )
    .padding(Theme.Spacing.lg)
    .frame(width: 320)
    .background(Theme.bgSurface)
}
#endif
