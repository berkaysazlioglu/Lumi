import LumiKit
import LumiState
import SwiftUI

/// Header sağ ikon butonu (v1 Header.tsx: 32×32, hover'da elevated zemin).
struct HeaderIconButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(isHovering || isActive ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
