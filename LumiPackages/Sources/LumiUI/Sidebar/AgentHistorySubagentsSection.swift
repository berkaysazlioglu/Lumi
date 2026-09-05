import AppKit
import LumiKit
import SwiftUI

/// Detay kartının SUBAGENTS (N) bölümü: her alt ajan bir satır kartı —
/// durum ikonu, ad, tür rozeti, mesaj sayısı ve log'u Finder'da açan düğme.
struct AgentHistorySubagentsSection: View {
    let subagents: [AgentHistorySubagent]

    var body: some View {
        AgentHistorySection(title: "Subagents (\(subagents.count))", icon: "cpu") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(subagents) { subagent in row(subagent) }
            }
        }
    }

    private func row(_ subagent: AgentHistorySubagent) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            Text(subagent.name)
                .font(Theme.Typography.ui(.body))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let kind = subagent.kind {
                Badge(text: kind, size: .caption, weight: .medium, style: .neutral, shape: .capsule)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            if subagent.messageCount > 0 {
                Text("\(subagent.messageCount) msgs")
                    .font(Theme.Typography.ui(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
            }
            IconButton(systemName: "doc.text", label: "Reveal subagent log in Finder", size: .caption) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: subagent.logPath)])
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Row.commit)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .help(subagent.model.map { "\(subagent.name) · \($0)" } ?? subagent.name)
    }
}
