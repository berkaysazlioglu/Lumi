import AppKit
import LumiKit
import LumiState
import SwiftUI

/// Proje görünümü modalı (karar 120): proje sağ tık menüsündeki `Appearance…`.
///
/// Solda Projects'teki tüm projeler (açılışta sağ tıklanan seçili), sağda
/// seçili projenin rengi, kök checkout ikonu ve başlığı. Taslak YOK — her
/// değişiklik anında config'e yazılır ve arkadaki panelde/kartlarda canlı
/// görünür; altta yalnız `Reset` ve `Done` (Esc/↩) durur.
public struct ProjectAppearanceOverlay: View {
    @Shell private var shell
    /// Metin alanlarının yerel taslağı: config'e normalize (kırpılmış) değer
    /// yazılır, alan kullanıcının yazdığını korur — yoksa yazarken boşluk yutulurdu.
    @State private var titleDraft = ""
    @State private var emojiDraft = ""
    @FocusState private var isEmojiFocused: Bool

    public init() {}

    private static var panelWidth: CGFloat { Theme.scaled(720) }
    private static var panelHeight: CGFloat { Theme.scaled(520) }
    private static var listWidth: CGFloat { Theme.scaled(220) }
    private static var swatchSize: CGFloat { Theme.scaled(22) }
    private static var symbolCell: CGFloat { Theme.scaled(32) }
    private static var emojiFieldWidth: CGFloat { Theme.scaled(64) }
    private static var titleFieldWidth: CGFloat { Theme.scaled(240) }
    private static let symbolColumns = 8

    private var projectPath: String? { shell.dialogs.projectAppearanceDialog?.projectPath }

    private var appearance: ProjectAppearance {
        projectPath.map { shell.settings.current.appearance(ofProject: $0) } ?? .none
    }

    public var body: some View {
        ModalOverlay(onDismiss: dismiss) {
            Panel(variant: .modal) {
                VStack(spacing: 0) {
                    header
                    divider
                    if let projectPath, let project = shell.repos.repo(at: projectPath) {
                        HStack(spacing: 0) {
                            projectList
                                .frame(width: Self.listWidth)
                            Rectangle().fill(Theme.border).frame(width: Theme.Stroke.hairline)
                            detail(project)
                        }
                    } else {
                        Text("Project is no longer available.")
                            .font(Theme.Typography.bodyMono)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    divider
                    footer
                }
            }
            .frame(width: Self.panelWidth, height: Self.panelHeight)
        }
        .onChange(of: projectPath, initial: true) { _, _ in loadDrafts() }
    }

    // MARK: - Başlık / alt bar

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Appearance")
                    .font(Theme.Typography.mono(.headline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Color for the project's terminals, icon and title for its main checkout")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            IconButton(
                systemName: "xmark", label: "Close appearance",
                side: Theme.scaled(28), cornerRadius: Theme.Radius.md, action: dismiss
            )
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private var footer: some View {
        HStack {
            LumiActionButton(title: "Reset") {
                guard let projectPath else { return }
                shell.settings.resetProjectAppearance(for: projectPath)
                titleDraft = ""
                emojiDraft = ""
            }
            .disabled(appearance.isEmpty)
            Spacer()
            LumiActionButton(title: "Done", kind: .primary, action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.Spacing.xxl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: Theme.Stroke.hairline)
    }

    // MARK: - Proje listesi

    private var projectList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                ForEach(shell.workspaces.addedProjects, id: \.path) { project in
                    ProjectAppearanceListRow(
                        name: project.name,
                        appearance: shell.settings.current.appearance(ofProject: project.path),
                        isSelected: project.path == projectPath
                    ) {
                        shell.dialogs.selectProjectAppearance(project.path)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xl)
        }
    }

    // MARK: - Ayrıntı

    private func detail(_ project: Repo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LumiField(title: "Color", hint: "Border and header of \(project.name)'s terminals, including its workspaces") {
                    colorRow(project.path)
                }
                LumiField(title: "Main checkout icon", hint: "Shown next to the main checkout in Projects") {
                    iconPicker(project.path)
                }
                LumiField(
                    title: "Main checkout title",
                    hint: "Up to \(ProjectRootTitle.maxLength) characters — empty uses \"\(ProjectRootTitle.defaultTitle)\"",
                    isLast: true
                ) {
                    LumiTextInput(
                        text: Binding(
                            get: { titleDraft },
                            set: { updateTitle($0, projectPath: project.path) }
                        ),
                        placeholder: ProjectRootTitle.defaultTitle,
                        width: Self.titleFieldWidth,
                        onSubmit: dismiss
                    )
                }
            }
            .padding(Theme.Spacing.xxl)
        }
    }

    private func colorRow(_ projectPath: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(ProjectColor.allCases, id: \.self) { color in
                swatch(title: color.title, color: Theme.projectColor(color), isSelected: appearance.color == color) {
                    shell.settings.setProjectColor(color, for: projectPath)
                }
            }
            swatch(title: "None", color: nil, isSelected: appearance.color == nil) {
                shell.settings.setProjectColor(nil, for: projectPath)
            }
        }
    }

    private func swatch(title: String, color: Color?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                ProjectColorDot(color: color, size: Self.swatchSize)
                    .padding(Theme.Spacing.xxs)
                    .overlay(
                        Circle().strokeBorder(
                            isSelected ? Theme.textPrimary : .clear,
                            lineWidth: Theme.Stroke.graph
                        )
                    )
                Text(title)
                    .font(Theme.Typography.captionMono)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconPicker(_ projectPath: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(Self.symbolCell), spacing: Theme.Spacing.sm),
                    count: Self.symbolColumns
                ),
                alignment: .leading,
                spacing: Theme.Spacing.sm
            ) {
                ForEach(ProjectIcon.symbolNames, id: \.self) { name in
                    iconCell(.symbol(name), label: name) {
                        emojiDraft = ""
                        shell.settings.setProjectIcon(.symbol(name), for: projectPath)
                    }
                }
            }
            HStack(spacing: Theme.Spacing.md) {
                Text("Emoji")
                    .font(Theme.Typography.labelMono)
                    .foregroundStyle(Theme.textSecondary)
                LumiTextInput(
                    text: Binding(
                        get: { emojiDraft },
                        set: { updateEmoji($0, projectPath: projectPath) }
                    ),
                    placeholder: "🙂",
                    width: Self.emojiFieldWidth,
                    focus: $isEmojiFocused
                )
                LumiActionButton(title: "Emoji Picker…") {
                    // Palet seçimi odaktaki alana yazar: önce alan odaklanır.
                    isEmojiFocused = true
                    DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(nil) }
                }
            }
        }
    }

    private func iconCell(_ icon: ProjectIcon, label: String, action: @escaping () -> Void) -> some View {
        let isSelected = appearance.resolvedIcon == icon
        return Button(action: action) {
            ProjectIconView(
                icon: icon, size: .title,
                color: isSelected ? Theme.accentPrimary : Theme.textSecondary
            )
            .frame(width: Self.symbolCell, height: Self.symbolCell)
            .background(isSelected ? Theme.accentPrimary.opacity(Self.selectedFillOpacity) : Theme.bgDeep)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(isSelected ? Theme.accentPrimary : Theme.border, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Seçili hücre zemini (`ExplorerRowView` seçim tonuyla aynı).
    private static let selectedFillOpacity = 0.15

    // MARK: - Taslaklar

    private func loadDrafts() {
        titleDraft = appearance.rootTitle ?? ""
        if case .emoji(let value) = appearance.icon {
            emojiDraft = value
        } else {
            emojiDraft = ""
        }
    }

    private func updateTitle(_ raw: String, projectPath: String) {
        let limited = String(raw.prefix(ProjectRootTitle.maxLength))
        titleDraft = limited
        guard ProjectRootTitle.normalized(limited) != appearance.rootTitle else { return }
        shell.settings.setProjectRootTitle(limited, for: projectPath)
    }

    /// Alan tek emoji tutar: yeni yazılan/palet seçilen karakter eskisinin
    /// yerine geçer. Geçersiz girdi (harf, birden çok grapheme) ikonu değiştirmez;
    /// alan boşaltılırsa emoji kalkar ve varsayılan ikona dönülür.
    private func updateEmoji(_ raw: String, projectPath: String) {
        let candidate = raw.last.map(String.init) ?? ""
        if candidate.isEmpty {
            emojiDraft = ""
            if case .emoji = appearance.icon { shell.settings.setProjectIcon(nil, for: projectPath) }
            return
        }
        guard let icon = ProjectIcon.emoji(from: candidate) else {
            emojiDraft = appearance.icon.flatMap { if case .emoji(let value) = $0 { value } else { nil } } ?? ""
            return
        }
        emojiDraft = candidate
        shell.settings.setProjectIcon(icon, for: projectPath)
    }

    private func dismiss() {
        guard let state = shell.dialogs.projectAppearanceDialog else { return shell.dialogs.dismiss() }
        shell.dialogs.dismiss(.projectAppearance(state))
    }
}

/// Sol listedeki proje: ikon (kök checkout'unki) · ad · renk noktası.
private struct ProjectAppearanceListRow: View {
    let name: String
    let appearance: ProjectAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HoverReader { isHovering in
            Button(action: action) {
                HStack(spacing: Theme.Spacing.sm) {
                    ProjectIconView(
                        icon: appearance.resolvedIcon,
                        color: isSelected ? Theme.accentPrimary : Theme.textMuted
                    )
                    .frame(width: Theme.Row.iconColumn)
                    Text(name)
                        .font(Theme.Typography.mono(.body, weight: .medium))
                        .foregroundStyle(isSelected || isHovering ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let color = appearance.color {
                        ProjectColorDot(color: Theme.projectColor(color))
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Theme.bgElevated : (isHovering ? Theme.bgElevated.opacity(Self.hoverOpacity) : .clear))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private static let hoverOpacity = 0.6
}

#if DEBUG
#Preview("ProjectAppearanceOverlay") {
    ProjectAppearanceOverlay()
        .frame(width: 900, height: 640)
        .environment(\.shell, ShellContext.preview())
}
#endif
