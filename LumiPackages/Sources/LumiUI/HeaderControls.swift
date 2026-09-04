import LumiKit
import LumiState
import SwiftUI

/// Header ikon butonu (ince bar: 26×26, hover'da elevated zemin).
struct HeaderIconButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(foreground)
                .frame(width: TopBarMetrics.controlHeight, height: TopBarMetrics.controlHeight)
                .background(isHovering || isActive ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        if isActive { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }
}
