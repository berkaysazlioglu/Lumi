import SwiftUI
import LumiMobileKit

/// A project's identity icon (Mac decision 120): its emoji, or its SF Symbol
/// in the accent color; `folder` when none was chosen.
struct ProjectIconView: View {
    let icon: ProjectIconID?
    var font: Font = .headline

    static let defaultSymbol = "folder"

    var body: some View {
        switch icon {
        case let .emoji(value)?:
            Text(value).font(font)
        case let .symbol(name)?:
            symbol(name)
        case nil:
            symbol(Self.defaultSymbol)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(font)
            .foregroundStyle(LumiPalette.accent)
    }
}

/// The 6pt project color dot (Mac `ProjectColorDot`).
struct ProjectColorDot: View {
    let color: ProjectColorID

    static let size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(LumiPalette.projectColor(color))
            .frame(width: Self.size, height: Self.size)
            .accessibilityLabel("\(color.rawValue) project")
    }
}
