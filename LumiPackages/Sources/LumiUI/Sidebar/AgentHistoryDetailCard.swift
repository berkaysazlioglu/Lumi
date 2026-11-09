import AppKit
import LumiKit
import SwiftUI

/// Agent History satırı açıldığında görünen detay kartı (Orca
/// `SessionInlineDetails` paritesi).
///
/// Üstte tonlu, sarmalanan aksiyon şeridi (Resume / Copy Command / View Log /
/// Export), altında
/// bölümler: FIRST PROMPT ("You" kartı + Copy), LATEST TURNS (rol etiketli
/// kartlar), SUBAGENTS (N) ve WORKTREE (branch + kompakt yol).
struct AgentHistoryDetailCard: View {
    let entry: AgentHistoryEntry
    let onResume: () -> Void
    let onCopyCommand: () -> Void
    let onRevealLog: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionBar
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let firstPrompt = entry.firstPrompt {
                    AgentHistorySection(title: "First prompt", icon: "text.quote") {
                        AgentHistoryTurnCard(
                            turn: AgentHistoryTurn(role: .user, text: firstPrompt),
                            onCopy: { copy(firstPrompt) }
                        )
                    }
                }
                AgentHistorySection(title: "Latest turns", icon: "bubble.left") {
                    if entry.recentTurns.isEmpty {
                        Text("No conversation preview available")
                            .font(Theme.Typography.ui(.body))
                            .foregroundStyle(Theme.textMuted)
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            ForEach(entry.recentTurns) { turn in AgentHistoryTurnCard(turn: turn) }
                        }
                    }
                }
                if !entry.subagents.isEmpty {
                    AgentHistorySubagentsSection(subagents: entry.subagents)
                }
                worktree
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }

    // MARK: - Parçalar

    /// Düğmeler doğal genişliklerinde kalır, sığmayan alt satıra iner (Orca
    /// `flex-wrap`) — dar panelde etiket kelime ortasından kırılmaz.
    private var actionBar: some View {
        FlowLayout(spacing: Theme.Spacing.sm) {
            action("Resume", icon: "play.fill", isPrimary: true, action: onResume)
                .disabled(entry.resumeCommand == nil)
            action("Copy Command", icon: "doc.on.doc", action: onCopyCommand)
                .disabled(entry.resumeCommand == nil)
            action("View Log", icon: "doc.text", action: onRevealLog)
            action("Export", icon: "square.and.arrow.up", action: onExport)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
        }
    }

    private func action(
        _ title: String, icon: String, isPrimary: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon).accessibilityHidden(true)
                Text(title).lineLimit(1)
            }
            .font(Theme.Typography.ui(.label, weight: .medium))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Spacing.xxl + Theme.Spacing.xs)
            .fixedSize()
        }
        .buttonStyle(
            HoverButtonStyle(
                foreground: isPrimary ? .white : Theme.textPrimary,
                hoverForeground: isPrimary ? .white : Theme.textPrimary,
                background: isPrimary ? Theme.accentVivid : Theme.bgDeep,
                hoverBackground: isPrimary ? Theme.accentDeep : Theme.border
            )
        )
        .fixedSize()
    }

    @ViewBuilder
    private var worktree: some View {
        if entry.gitBranch != nil || entry.compactPath != nil {
            AgentHistorySection(title: "Worktree", icon: "folder.badge.gearshape") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    if let branch = entry.gitBranch {
                        HStack(spacing: Theme.Spacing.sm) {
                            Text("Branch".uppercased())
                                .font(Theme.Typography.ui(.caption, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(Theme.textSecondary)
                            Text(branch)
                                .font(Theme.Typography.mono(.caption))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    if let path = entry.compactPath {
                        Text(path)
                            .font(Theme.Typography.mono(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(entry.cwd ?? path)
                    }
                }
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

/// Kart bölümü: ikon + büyük harfli başlık + içerik.
struct AgentHistorySection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.Typography.ui(.caption))
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(Theme.Typography.ui(.label, weight: .semibold))
                    .tracking(0.6)
            }
            .foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}

/// Tek konuşma turu — büyük harfli rol etiketi ("YOU" / "AGENT") + metin.
/// `onCopy` verilirse sağ üstte Copy düğmesi çıkar (ilk istem kartı).
struct AgentHistoryTurnCard: View {
    let turn: AgentHistoryTurn
    var onCopy: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(turn.role == .user ? "You" : "Agent")
                    .textCase(.uppercase)
                    .font(Theme.Typography.ui(.caption, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if let onCopy {
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(Theme.Typography.ui(.caption))
                    }
                    .buttonStyle(HoverButtonStyle(cornerRadius: Theme.Radius.sm))
                    .help("Copy prompt")
                }
            }
            Text(turn.text)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(turn.role == .user ? Theme.accentPrimary.opacity(Self.userTint) : Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private static let userTint = 0.08
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
            ],
            subagents: [
                AgentHistorySubagent(id: "a1", name: "Orca vs Lumi Explorer", kind: "Explore", messageCount: 89, logPath: "/tmp/a1"),
                AgentHistorySubagent(id: "a2", name: "Faz 1: Explorer yenileme", kind: "general-purpose", messageCount: 145, logPath: "/tmp/a2"),
            ]
        ),
        onResume: {}, onCopyCommand: {}, onRevealLog: {},
        onExport: {}
    )
    .padding(Theme.Spacing.lg)
    .frame(width: 340)
    .background(Theme.bgSurface)
}
#endif
