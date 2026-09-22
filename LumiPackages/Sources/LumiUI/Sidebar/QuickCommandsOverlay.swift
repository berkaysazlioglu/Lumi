import LumiKit
import LumiState
import SwiftUI

/// Projenin hızlı komut düzenleyicisi (karar 92): proje satırının sağ tık
/// menüsündeki `Actions…`. Settings kabuğunun dili — solda komut listesi,
/// sağda seçili komutun formu.
///
/// Düzenlemeler kaydedilene kadar modal yerel TASLAKLARDIR: komutlar arasında
/// gezinmek yarım kalan düzenlemeyi kaybetmez, Save ile config'e yazılır.
/// Modal kapanınca kaydedilmemiş taslaklar atılır.
public struct QuickCommandsOverlay: View {
    @Shell private var shell
    @State private var selectedID: String?
    /// Düzenlenmiş (ya da hiç kaydedilmemiş) komutların taslakları.
    @State private var drafts: [String: ProjectQuickCommand] = [:]
    /// Kaydedilmemiş yeni komutlar, eklenme sırasıyla.
    @State private var newIDs: [String] = []

    public init() {}

    private static var panelWidth: CGFloat { Theme.scaled(860) }
    private static var panelHeight: CGFloat { Theme.scaled(640) }
    private static var listWidth: CGFloat { Theme.scaled(220) }

    private var projectPath: String? {
        guard case .quickCommands(let path) = shell.dialogs.active else { return nil }
        return path
    }

    public var body: some View {
        ModalOverlay(onDismiss: dismiss) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    divider
                    if let projectPath, let project = shell.repos.repo(at: projectPath) {
                        HStack(spacing: 0) {
                            commandList(projectPath: projectPath)
                                .frame(width: Self.listWidth)
                            Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                            detail(project: project)
                        }
                    } else {
                        Text("Project is no longer available.")
                            .font(Theme.Typography.bodyMono)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
        .onAppear(perform: selectInitialCommand)
    }

    // MARK: - Başlık

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Actions")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            IconButton(
                systemName: "xmark", label: "Close actions",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: dismiss
            )
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var subtitle: String {
        let name = projectPath.flatMap { shell.repos.repo(at: $0)?.name } ?? "this project"
        return "Commands for \(name) — run them from any checkout's right-click menu"
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    // MARK: - Liste

    private func commandList(projectPath: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HoverReader { isHovering in
                Button { addCommand(projectPath: projectPath) } label: {
                    Label("New Action", systemImage: "plus")
                        .font(Theme.Typography.mono(.body, weight: .medium))
                        .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isHovering ? Theme.bgElevated : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    ForEach(rows(projectPath: projectPath)) { command in
                        QuickCommandListRow(
                            title: command.name,
                            isSelected: selectedID == command.id,
                            hasChanges: hasChanges(command.id),
                            isGenerating: shell.quickCommands.isGenerating(command.id)
                        ) { selectedID = command.id }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
    }

    /// Kaydedilmiş komutlar (taslaklarıyla) + kaydedilmemiş yeniler.
    private func rows(projectPath: String) -> [ProjectQuickCommand] {
        let saved = shell.quickCommands.commands(for: projectPath).map { drafts[$0.id] ?? $0 }
        return saved + newIDs.compactMap { drafts[$0] }
    }

    // MARK: - Detay

    @ViewBuilder
    private func detail(project: Repo) -> some View {
        if let selectedID, let command = draft(selectedID) {
            QuickCommandEditorView(
                command: Binding(get: { draft(selectedID) ?? command }, set: { drafts[selectedID] = $0 }),
                project: project,
                isSaved: saved(selectedID) != nil,
                hasChanges: hasChanges(selectedID),
                onSave: { save(selectedID) },
                onDiscard: { discard(selectedID) },
                onDelete: { delete(selectedID) },
                onGenerate: { generate(selectedID, project: project) }
            )
            .id(selectedID)
        } else {
            emptyState(projectPath: project.path)
        }
    }

    private func emptyState(projectPath: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "bolt")
                .font(Theme.Typography.ui(.heading))
                .foregroundStyle(Theme.textMuted)
                .accessibilityHidden(true)
            Text("No actions yet")
                .font(Theme.Typography.mono(.base, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Describe a command and let Claude write it, or write the script yourself.")
                .font(Theme.Typography.labelMono)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            LumiActionButton(title: "New Action", kind: .primary) { addCommand(projectPath: projectPath) }
        }
        .padding(Theme.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Taslak işlemleri

    private func saved(_ id: String) -> ProjectQuickCommand? {
        shell.quickCommands.commands.first { $0.id == id }
    }

    private func draft(_ id: String) -> ProjectQuickCommand? {
        drafts[id] ?? saved(id)
    }

    private func hasChanges(_ id: String) -> Bool {
        guard let draft = drafts[id] else { return false }
        return draft != saved(id)
    }

    private func selectInitialCommand() {
        guard let projectPath else { return }
        if let first = shell.quickCommands.commands(for: projectPath).first {
            selectedID = first.id
        } else {
            addCommand(projectPath: projectPath)
        }
    }

    private func addCommand(projectPath: String) {
        let command = ProjectQuickCommand(projectPath: projectPath, name: "", script: "")
        drafts[command.id] = command
        newIDs.append(command.id)
        selectedID = command.id
    }

    private func save(_ id: String) {
        guard let command = drafts[id] else { return }
        Task {
            guard await shell.quickCommands.save(command) else { return }
            // Kayıt sırasında kullanıcı yazmaya devam ettiyse taslak korunur.
            if drafts[id] == command { drafts[id] = nil }
            newIDs.removeAll { $0 == id }
        }
    }

    private func discard(_ id: String) {
        drafts[id] = nil
    }

    private func delete(_ id: String) {
        let isNew = newIDs.contains(id)
        drafts[id] = nil
        newIDs.removeAll { $0 == id }
        selectedID = projectPath.flatMap { path in rows(projectPath: path).first { $0.id != id }?.id }
        guard !isNew else { return }
        Task { await shell.quickCommands.delete(id: id) }
    }

    /// Sonuç, istek hangi taslak için yapıldıysa ona yazılır — kullanıcı bu
    /// arada başka bir komuta geçmiş olabilir.
    private func generate(_ id: String, project: Repo) {
        guard let command = draft(id) else { return }
        let request = QuickCommandGenerationRequest(
            projectPath: project.path, projectName: project.name,
            description: command.request, currentScript: command.script
        )
        Task {
            guard let script = await shell.quickCommands.generate(draftID: id, request: request),
                  var latest = draft(id) else { return }
            latest.script = script
            if latest.name.trimmingCharacters(in: .whitespaces).isEmpty {
                latest.name = QuickCommandNaming.suggestedName(from: command.request)
            }
            drafts[id] = latest
        }
    }

    private func dismiss() {
        guard let projectPath else { return shell.dialogs.dismiss() }
        shell.dialogs.dismiss(.quickCommands(projectPath: projectPath))
    }
}

/// Sol listedeki satır: ad (boşsa `Untitled`), kaydedilmemiş değişiklik
/// noktası ve üretim sürerken ilerleme göstergesi.
private struct QuickCommandListRow: View {
    let title: String
    let isSelected: Bool
    let hasChanges: Bool
    let isGenerating: Bool
    let action: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: action) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "bolt")
                        .font(Theme.Typography.ui(.label))
                        .foregroundStyle(isSelected ? Theme.accentPrimary : Theme.textMuted)
                        .accessibilityHidden(true)
                    Text(displayTitle)
                        .font(Theme.Typography.mono(.body, weight: .medium))
                        .foregroundStyle(foreground(isHovering: isHovering))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if isGenerating {
                        ProgressView().controlSize(.mini)
                    } else if hasChanges {
                        Circle().fill(Theme.warning)
                            .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
                            .help("Unsaved changes")
                    }
                }
                .padding(Theme.Spacing.md)
                .background(background(isHovering: isHovering))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(hasChanges ? "\(displayTitle), unsaved changes" : displayTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func foreground(isHovering: Bool) -> Color {
        if isSelected { return Theme.accentPrimary }
        return isHovering ? Theme.textPrimary : Theme.textSecondary
    }

    private func background(isHovering: Bool) -> Color {
        if isSelected { return Theme.accentVivid.opacity(0.08) }
        return isHovering ? Theme.bgElevated : .clear
    }
}

#if DEBUG
#Preview("QuickCommandsOverlay") {
    QuickCommandsOverlay()
        .frame(width: 900, height: 700)
        .environment(\.shell, ShellContext.preview())
}
#endif
