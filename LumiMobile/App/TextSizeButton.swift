import SwiftUI

/// `Aa` toolbar button: a small popover with A− / size / A+ for the TUI text.
/// The size lives in `@AppStorage` so every chat and the terminal share it.
struct TextSizeButton: View {
    @AppStorage(TUIStyle.sizeKey) private var size = TUIStyle.defaultSize
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel("Text size")
        .popover(isPresented: $showing) {
            HStack(spacing: 16) {
                stepButton("textformat.size.smaller", delta: -1)
                Text("\(Int(size)) pt")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 52)
                stepButton("textformat.size.larger", delta: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .lumiThemed()
            .presentationCompactAdaptation(.popover)
        }
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        let next = size + delta
        return Button {
            size = next
        } label: {
            Image(systemName: symbol).font(.title3).frame(width: 36, height: 36)
        }
        .disabled(!TUIStyle.sizeRange.contains(next))
    }
}
