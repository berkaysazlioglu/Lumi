import LumiState
import SwiftUI

/// FileViewer başlığındaki kapsül düğme etiketi — `Mention in Chat` ve
/// `Save` aynı dili konuşur.
struct ViewerPillLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.accentPrimary

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(Theme.Typography.mono(.caption, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.md)
        // 3pt: markdown anahtarıyla hizalı ölçek dışı ara değer.
        .padding(.vertical, Theme.scaled(3))
        .background(tint.opacity(0.18))
        .clipShape(Capsule())
        .contentShape(Capsule())
    }
}

/// Karar 110: `Save` (⌘S). Taslak yokken pasif; dosya yüklendikten sonra
/// diskte değiştiyse yerini `Overwrite | Reload` seçimine bırakır.
struct SaveFileButton: View {
    let store: FileViewerStore

    var body: some View {
        if store.saveState == .conflict {
            conflictChoice
        } else {
            Button {
                Task { await store.save() }
            } label: {
                ViewerPillLabel(
                    title: store.saveState == .saving ? "Saving…" : "Save",
                    systemImage: "square.and.arrow.down"
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!store.hasUnsavedChanges || store.saveState == .saving)
            .opacity(store.hasUnsavedChanges ? 1 : 0.4)
            .help(store.hasUnsavedChanges ? "Save changes to disk (⌘S)" : "No unsaved changes")
            .accessibilityLabel("Save file")
        }
    }

    private var conflictChoice: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Changed on disk")
                .font(Theme.Typography.mono(.caption, weight: .semibold))
                .foregroundStyle(Theme.warning)
            Button {
                Task { await store.save(overwrite: true) }
            } label: {
                ViewerPillLabel(title: "Overwrite", systemImage: "square.and.arrow.down", tint: Theme.warning)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("s", modifiers: .command)
            .help("Replace the file on disk with your version (⌘S)")
            Button {
                Task { await store.reloadFromDisk() }
            } label: {
                ViewerPillLabel(title: "Reload", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Discard your edits and load the version on disk")
        }
    }
}

/// Karar 110: kaydedilmemiş taslakla kapatma / başka dosyaya geçme onayı.
/// Panelin üstünde durur; Escape vazgeçer.
struct UnsavedChangesPrompt: View {
    let store: FileViewerStore

    var body: some View {
        ZStack {
            Color.black.opacity(ModalOverlay<EmptyView>.scrimOpacity)
                .contentShape(Rectangle())
                .onTapGesture(perform: store.cancelDiscard)
                .accessibilityHidden(true)
            Panel(variant: .modal) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Unsaved changes")
                        .font(Theme.Typography.titleMono)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\((store.filePath as NSString).lastPathComponent) has changes that aren't saved.")
                        .font(Theme.Typography.bodyMono)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: Theme.Spacing.md) {
                        LumiActionButton(title: "Discard") { Task { await store.confirmDiscard() } }
                        Spacer()
                        LumiActionButton(title: "Cancel", action: store.cancelDiscard)
                            .keyboardShortcut(.cancelAction)
                        LumiActionButton(title: "Save", kind: .primary) { Task { await store.saveAndContinue() } }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(Theme.Spacing.xxl)
                .frame(width: Theme.scaled(420))
            }
        }
        .onExitCommand(perform: store.cancelDiscard)
    }
}
