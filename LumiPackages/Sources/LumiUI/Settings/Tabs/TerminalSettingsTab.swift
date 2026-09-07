import LumiKit
import SwiftUI

/// Terminal fontu ve caret'i — anlık uygulanır (karar 3).
struct TerminalSettingsTab: SettingsTabContent {
    static let tab: SettingsTab = .terminal

    @Shell private var shell

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LumiSectionTitle(
                title: "Terminal",
                description: "Font and cursor. Changes apply instantly."
            )
            LumiField(title: "Font Family", hint: "Monospace fonts installed on this Mac") {
                fontFamilyPicker
            }
            LumiField(title: "Font Size", hint: AppConfig.terminalFontSizeHint) {
                fontSizeStepper
            }
            LumiField(title: "Cursor", hint: "Caret shape and blinking") {
                cursorControls
            }
            LumiField(
                title: "Auto-Minimize on Send",
                hint: "Minimize a chat while the assistant works on your message; "
                    + "bring it back when it finishes or waits for input."
            ) {
                LumiToggleSwitch(
                    isOn: Binding(
                        get: { shell.settings.current.autoMinimizeOnSend },
                        set: { shell.settings.setAutoMinimizeOnSend($0) }
                    ),
                    label: "Auto-minimize on send"
                )
            }
            LumiField(
                title: "Agent Status Hooks",
                hint: "Install Lumi hooks into Claude Code and Codex so working / waiting / idle "
                    + "come straight from the agent. Turning this off removes the hooks and falls "
                    + "back to terminal-title heuristics.",
                isLast: true
            ) {
                LumiToggleSwitch(
                    isOn: Binding(
                        get: { shell.settings.current.agentHooksEnabled },
                        set: { shell.settings.setAgentHooksEnabled($0) }
                    ),
                    label: "Agent status hooks"
                )
            }
        }
    }

    private var fontFamilyPicker: some View {
        Picker(
            "",
            selection: Binding(
                get: { shell.settings.current.terminalFontFamily },
                set: { shell.settings.setTerminalFontFamily($0) }
            )
        ) {
            Text("JetBrains Mono (Default)").tag("")
            Divider()
            ForEach(LumiFonts.availableMonospaceFamilies, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .labelsHidden()
        .font(Theme.Typography.bodyMono)
        .frame(width: 260, alignment: .leading)
        .accessibilityLabel("Terminal font family")
    }

    private var fontSizeStepper: some View {
        Stepper(
            "\(shell.settings.current.terminalFontSize) px",
            value: Binding(
                get: { shell.settings.current.terminalFontSize },
                set: { shell.settings.setTerminalFontSize($0) }
            ),
            in: AppConfig.terminalFontSizeRange
        )
        .font(Theme.Typography.bodyMono)
        .foregroundStyle(Theme.textPrimary)
        .frame(width: 140, alignment: .leading)
    }

    private var cursorControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LumiSegmented(
                options: TerminalCursorShape.allCases.map {
                    .init(value: $0, label: $0.displayLabel)
                },
                selection: Binding(
                    get: { TerminalCursorShape.parse(shell.settings.current.terminalCursorStyle) },
                    set: { shell.settings.setTerminalCursorStyle($0) }
                )
            )
            // 10pt: ölçek dışı ara değer (v1 paritesi korunuyor).
            HStack(spacing: 10) {
                Text("Blink")
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
                LumiToggleSwitch(
                    isOn: Binding(
                        get: { shell.settings.current.terminalCursorBlink },
                        set: { shell.settings.setTerminalCursorBlink($0) }
                    ),
                    label: "Cursor blink"
                )
            }
        }
    }
}

#if DEBUG
#Preview("Terminal") {
    SettingsTabPreview(.terminal)
}
#endif
