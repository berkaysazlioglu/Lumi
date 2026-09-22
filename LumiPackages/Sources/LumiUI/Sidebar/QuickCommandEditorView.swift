import LumiKit
import LumiState
import SwiftUI

/// Hızlı komut formu (karar 92): ad · Claude'a tarif + Generate · script ·
/// anahtar listesi · Save / Discard / Delete. Taslak durumu ve kayıt
/// `QuickCommandsOverlay`'dedir; bu görünüm yalnız bağlı taslağı düzenler.
struct QuickCommandEditorView: View {
    @Binding var command: ProjectQuickCommand
    let project: Repo
    let isSaved: Bool
    let hasChanges: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onDelete: () -> Void
    let onGenerate: () -> Void

    @Shell private var shell
    @State private var isConfirmingDelete = false

    private static var scriptHeight: CGFloat { Theme.scaled(210) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isStartApp {
                        startAppIntro
                    } else {
                        LumiField(title: "Name", hint: nil) {
                            LumiTextInput(text: $command.name, placeholder: "Open in Unity", autofocus: !isSaved)
                        }
                    }
                    LumiField(
                        title: "Ask Claude",
                        hint: "Describe the command. Claude explores \(project.name) — it may run commands to look around — and writes the script."
                    ) {
                        requestField
                    }
                    LumiField(title: "Script", hint: scriptHint, isLast: true) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            LumiCodeEditor(text: $command.script, isEditable: !isGenerating)
                                .frame(height: Self.scriptHeight)
                            placeholderList
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xxxl)
                .padding(.vertical, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
            footer
        }
    }

    private var isGenerating: Bool { shell.quickCommands.isGenerating(command.id) }

    private var isStartApp: Bool { command.role == .startApp }

    private var scriptHint: String {
        let base = "Runs with sh in a new terminal; the working directory is the checkout."
        return isStartApp ? base + " Leave empty to hide Start App." : base
    }

    private var startAppIntro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(QuickCommandRole.startAppName)
                .font(Theme.Typography.mono(.title, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Shown first in every checkout's right-click menu when the script is set.")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.bottom, Theme.Spacing.xxl)
    }

    /// Start App'te boş gövdeyle Save = kaldırma (karar 93).
    private var canSave: Bool {
        guard !isGenerating, hasChanges || !isSaved else { return false }
        if isStartApp && isSaved { return true }
        return command.isValid
    }

    private var canGenerate: Bool {
        !isGenerating && !command.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Claude

    private var requestField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            TextField(requestPlaceholder, text: $command.request, axis: .vertical)
                .lineLimit(2...5)
                .font(Theme.Typography.bodyMono)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Theme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.border, lineWidth: Theme.Stroke.hairline)
                )
                .disabled(isGenerating)
            HStack(spacing: Theme.Spacing.md) {
                LumiActionButton(title: generateTitle, kind: .secondary, action: onGenerate)
                    .disabled(!canGenerate)
                if isGenerating {
                    ProgressView().controlSize(.small)
                    Text("Claude is exploring the project…")
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    private var requestPlaceholder: String {
        isStartApp
            ? "e.g. Open this checkout in the Unity version the project uses"
            : "e.g. Build a release and install it to /Applications"
    }

    private var generateTitle: String {
        command.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "✨ Generate" : "✨ Regenerate"
    }

    // MARK: - Anahtarlar

    private var placeholderList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(QuickCommandPlaceholder.allCases, id: \.self) { placeholder in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    Text(placeholder.token)
                        .font(Theme.Typography.mono(.label, weight: .semibold))
                        .foregroundStyle(Theme.accentPrimary)
                        .textSelection(.enabled)
                    Text(placeholder.summary)
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Text("Wrap them in double quotes: cd \"{path}\"")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, Theme.Spacing.xxs)
        }
    }

    private var deletePrompt: String {
        if isStartApp { return "Remove Start App from the menu?" }
        return isSaved ? "Delete this action?" : "Discard this new action?"
    }

    // MARK: - Alt şerit

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if isConfirmingDelete {
                Text(deletePrompt)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.error)
                LumiActionButton(title: isStartApp ? "Clear" : "Delete", kind: .primary) {
                    isConfirmingDelete = false
                    onDelete()
                }
                LumiActionButton(title: "Keep") { isConfirmingDelete = false }
            } else if !(isStartApp && !isSaved) {
                LumiActionButton(title: isStartApp ? "Clear" : "Delete") { isConfirmingDelete = true }
            }
            Spacer(minLength: 0)
            if isSaved && hasChanges {
                LumiActionButton(title: "Discard Changes", action: onDiscard)
            }
            LumiActionButton(title: "Save", kind: .primary, action: onSave)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}
