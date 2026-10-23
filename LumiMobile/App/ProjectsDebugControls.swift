import SwiftUI

/// Temporary test controls under the usage strip (to be removed once the look
/// is decided): wash the project color over its whole group, and step the
/// Projects text size up/down.
struct ProjectsDebugControls: View {
    static let tintKey = "projectsTintsGroups"

    @AppStorage(tintKey) private var tintsGroups = false
    @AppStorage(ProjectsRowMetrics.scaleKey) private var rowScale = 1.0

    private static let corner: CGFloat = 8

    var body: some View {
        HStack(spacing: 8) {
            control(tintsGroups ? "Group Color On" : "Group Color Off", symbol: "paintpalette",
                    isActive: tintsGroups) { tintsGroups.toggle() }
            control("A−", symbol: nil, isActive: false) { step(-1) }
                .disabled(rowScale <= ProjectsRowMetrics.scaleRange.lowerBound + 0.001)
            Text("\(Int((rowScale * 100).rounded()))%")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(LumiPalette.textSecondary)
                .frame(minWidth: 40)
            control("A+", symbol: nil, isActive: false) { step(1) }
                .disabled(rowScale >= ProjectsRowMetrics.scaleRange.upperBound - 0.001)
            Spacer(minLength: 0)
        }
    }

    private func step(_ direction: Double) {
        let next = rowScale + direction * ProjectsRowMetrics.scaleStep
        let range = ProjectsRowMetrics.scaleRange
        rowScale = (min(max(next, range.lowerBound), range.upperBound) * 10).rounded() / 10
    }

    private func control(_ title: String?, symbol: String?, isActive: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                if let title { Text(title) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? LumiPalette.accent : LumiPalette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LumiPalette.elevated, in: RoundedRectangle(cornerRadius: Self.corner))
            .overlay(RoundedRectangle(cornerRadius: Self.corner)
                .stroke(isActive ? LumiPalette.accent : LumiPalette.border, lineWidth: 1))
        }
        .buttonStyle(.borderless)
    }
}
