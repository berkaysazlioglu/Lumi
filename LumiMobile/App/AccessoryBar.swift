import SwiftUI
import LumiMobileKit

/// Accessory key bar: arrow keys, control keys, and free-text input.
/// Every button press or text submission is forwarded to the PTY via the `sendInput` closure.
struct AccessoryBar: View {
    /// Closure receiving raw bytes to send; the caller routes them to the PTY (arrow/control keys).
    let sendInput: (Data) -> Void
    /// Free-text submission; the caller writes the text, waits for settle, then sends Enter SEPARATELY.
    let submitText: (String) -> Void

    @State private var text: String = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 6) {
                // First row: arrow keys + control keys
                HStack(spacing: 6) {
                    accessoryButton("↑", key: .up)
                    accessoryButton("↓", key: .down)
                    accessoryButton("←", key: .left)
                    accessoryButton("→", key: .right)
                    Spacer()
                    accessoryButton("Esc",   key: .esc)
                    accessoryButton("Tab",   key: .tab)
                    accessoryButton("↵",     key: .enter)
                    accessoryButton("^C",    key: .ctrlC)
                }

                // Second row: free-text input + send
                HStack(spacing: 8) {
                    TextField("Send…", text: $text)
                        .lumiField()
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.send)
                        .focused($textFieldFocused)
                        .onSubmit { commitText() }

                    Button(action: commitText) {
                        Image(systemName: "arrow.up.circle.fill")
                            .imageScale(.large)
                    }
                    .disabled(text.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LumiPalette.background)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func accessoryButton(_ label: String, key: AccessoryKey) -> some View {
        Button(label) {
            sendInput(bytes(for: key))
        }
        .font(.system(.footnote, design: .monospaced).bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(LumiPalette.elevated, in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.primary)
    }

    private func commitText() {
        guard !text.isEmpty else { return }
        // "Send" = write text → settle → send Enter SEPARATELY (submitText). A combined
        // `text\r` in a single write is consumed by the Claude TUI as an Enter that arrives
        // before paste ingest finishes; the text appears but the line is never submitted.
        submitText(text)
        text = ""
    }
}

#if DEBUG
#Preview {
    AccessoryBar(sendInput: { _ in }, submitText: { _ in })
}
#endif
