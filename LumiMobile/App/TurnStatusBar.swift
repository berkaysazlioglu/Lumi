import SwiftUI
import LumiMobileKit
import LumiWire
import Foundation

/// Phase 2: live turn-status bar above the chat composer. Visible while working.
/// Left: spinner + "Running {n}s" (live via TimelineView). Middle: tool chip.
/// Right: Stop → Esc (0x1B), decision 104.
struct TurnStatusBar: View {
    let status: ChatTurnStatus
    let isStopping: Bool
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedLabel(now: context.date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let tool = status.tool {
                    Text(tool)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Button(isStopping ? "Stopping…" : "Stop", role: .destructive) { onStop() }
                    .font(.footnote.bold())
                    .disabled(isStopping)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func elapsedLabel(now: Date) -> String {
        guard let startedAtMs = status.startedAtMs else { return "Running" }
        let started = Date(timeIntervalSince1970: Double(startedAtMs) / 1000)
        let secs = max(0, Int(now.timeIntervalSince(started)))
        return "Running \(secs)s"
    }
}
