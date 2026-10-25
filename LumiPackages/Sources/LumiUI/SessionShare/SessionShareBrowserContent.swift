import LumiKit
import LumiState
import SwiftUI

/// Bağlı sunucunun gövdesi (karar 138): solda `All` + yükleyenler, sağda
/// oturumlar, altta seçili oturumun `Import…` düğmesi (proje seçtirir).
/// Silme yalnız kendi yüklediklerinde, satır içi onayla.
struct SessionShareBrowserContent: View {
    @Bindable var store: SessionShareStore
    /// Project seçicinin işaretli önerisi.
    let defaultProjectPath: String?
    @Shell private var shell
    @State private var isPickingProject = false

    private static var sidebarWidth: CGFloat { Theme.scaled(210) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                sessionList
            }
            SessionShareDivider()
            footer
        }
    }

    // MARK: - Sol panel

    private var sidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxxs) {
                uploaderRow(title: "All", count: store.sessions.count, isSelected: store.uploaderFilter == nil) {
                    store.uploaderFilter = nil
                }
                if !store.uploaders.isEmpty {
                    Text("UPLOADERS")
                        .font(Theme.Typography.labelMono)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xs)
                }
                ForEach(store.uploaders) { uploader in
                    uploaderRow(
                        title: uploader.id == store.info?.me.id ? "\(uploader.name) (You)" : uploader.name,
                        count: store.sessions.count { $0.uploader.id == uploader.id },
                        isSelected: store.uploaderFilter == uploader.id
                    ) { store.uploaderFilter = uploader.id }
                }
            }
            .padding(Theme.Spacing.sm)
        }
        .frame(width: Self.sidebarWidth)
        .background(Theme.bgDeep)
    }

    private func uploaderRow(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.mono(.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Theme.bgElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Liste

    private var sessionList: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let failure = store.listFailure {
                    SessionShareFailureView(failure: failure).padding(Theme.Spacing.xl)
                }
                if store.isRefreshing && store.sessions.isEmpty {
                    ProgressView().controlSize(.small).padding(Theme.Spacing.xl)
                } else if store.visibleSessions.isEmpty && store.listFailure == nil {
                    EmptyStatePlaceholder(
                        store.sessions.isEmpty
                            ? "No shared sessions yet. Right-click a session in Agent History ▸ Export to Server."
                            : "No sessions from this uploader",
                        density: .panel
                    )
                    .padding(Theme.Spacing.xl)
                }
                ForEach(store.visibleSessions) { session in
                    SessionShareRow(
                        session: session,
                        isSelected: store.selectedSessionID == session.id,
                        isMine: store.isMine(session),
                        isBusy: store.busySessionIDs.contains(session.id),
                        isConfirmingDelete: store.confirmingDeleteID == session.id,
                        onSelect: { store.selectedSessionID = session.id },
                        onImport: {
                            store.selectedSessionID = session.id
                            isPickingProject = true
                        },
                        onDelete: { store.confirmingDeleteID = session.id },
                        onConfirmDelete: { Task { await store.deleteSession(session.id) } },
                        onCancelDelete: { store.confirmingDeleteID = nil }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Alt şerit

    private var selected: SharedSession? {
        store.selectedSessionID.flatMap { id in store.sessions.first { $0.id == id } }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let selected {
                Text(selected.title)
                    .font(Theme.Typography.bodyMono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Select a session to import it into one of your projects")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: Theme.Spacing.md)
            LumiActionButton(title: "Close", action: store.closeBrowser)
            LumiActionButton(title: "Import…", kind: .primary) { isPickingProject = true }
                .disabled(selected == nil || selected.map { store.busySessionIDs.contains($0.id) } == true
                    || shell.agentHistory.isTransferring)
                .popover(isPresented: $isPickingProject, arrowEdge: .top) {
                    PopoverMenu(items: projectItems, dismiss: { isPickingProject = false }, width: nil)
                }
        }
        .padding(Theme.Spacing.xl)
    }

    /// "Import into" — Projects panelindeki projeler; sağ panelin projesi işaretli.
    private var projectItems: [PopoverMenu.Item] {
        let projects = shell.workspaces.addedProjects
        guard let selected, !projects.isEmpty else {
            return [.note("Add a project to Projects first")]
        }
        return [.section("Import into project")] + projects.map { project in
            .toggle(project.name, isOn: project.path == defaultProjectPath) {
                Task {
                    if await store.importSession(selected.id, into: project.path) { store.closeBrowser() }
                }
            }
        }
    }
}

/// Oturum satırı: başlık; altında sağlayıcı · proje · yükleyen · tarih.
private struct SessionShareRow: View {
    let session: SharedSession
    let isSelected: Bool
    let isMine: Bool
    let isBusy: Bool
    let isConfirmingDelete: Bool
    let onSelect: () -> Void
    let onImport: () -> Void
    let onDelete: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(session.title)
                    .font(Theme.Typography.ui(.base, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isBusy {
                ProgressView().controlSize(.small)
            } else if isConfirmingDelete {
                LumiActionButton(title: "Cancel", action: onCancelDelete)
                LumiActionButton(title: "Delete", kind: .destructive, action: onConfirmDelete)
            } else if isMine {
                IconButton(systemName: "trash", label: "Delete from server", size: .caption, role: .destructive, action: onDelete)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(isSelected ? Theme.bgElevated : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onImport)
        .onTapGesture(perform: onSelect)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var metadata: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let provider = session.provider {
                ProviderIcon(provider: provider, size: .caption)
            }
            if !session.project.isEmpty {
                Text(session.project).lineLimit(1)
                dot
            }
            Text(isMine ? "\(session.uploader.name) (You)" : session.uploader.name).lineLimit(1)
            dot
            Text(RelativeTimeFormatter.label(session.uploadedAt))
            if let size = session.sizeBytes {
                dot
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
        }
        .font(Theme.Typography.ui(.caption))
        .foregroundStyle(Theme.textMuted)
    }

    private var dot: some View {
        Text("·").accessibilityHidden(true)
    }
}
