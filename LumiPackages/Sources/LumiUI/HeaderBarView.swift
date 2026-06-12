import LumiKit
import LumiState
import SwiftUI

/// Üst header çubuğu (v1 paritesi, globals.css; spec/22). 52px, traffic
/// light hizasında. Sol grup: hamburger (sol panel) → logo + "Lumi" → repo
/// tab'leri → +. Orta: grid ayarı + New <Provider>. Sağ grup (32px ikon):
/// fullscreen (focus mode) · git · settings.
/// Topbar ölçüleri — LumiApp (titlebar büyütme) ile paylaşılır.
public enum TopBarMetrics {
    public static let height: CGFloat = 52
}

struct HeaderBarView: View {
    static let height: CGFloat = TopBarMetrics.height

    let workspace: WorkspaceStore
    let repoStore: RepoStore
    let terminals: TerminalListStore
    let personasStore: PersonasStore
    let settings: SettingsStore
    let usage: UsageStore

    @State private var isAddRepoHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Sol grup (v1 header-left, gap 12): hamburger → logo → tab'ler + (+)
            HStack(spacing: 12) {
                HeaderIconButton(
                    icon: "line.3.horizontal",
                    isActive: workspace.leftSidebarOpen,
                    action: { workspace.toggleLeftSidebar() }
                )
                logoView
                tabStrip
            }
            Spacer(minLength: 12)
            // Orta küme: kullanım göstergesi + grid ayarı + New <Provider>
            if let active = workspace.activeTab {
                HStack(spacing: 8) {
                    UsageIndicatorView(store: usage)
                    gridLayoutMenu(for: active)
                    NewTerminalButton(
                        provider: settings.current.aiProvider,
                        personas: personasStore.personas,
                        onNewProvider: {
                            terminals.spawn(in: active, command: settings.current.aiProvider.launchCommand)
                        },
                        onNewBash: { terminals.spawn(in: active, task: "Bash") },
                        onPersona: { personasStore.spawn($0, repoPath: active) }
                    )
                }
                .padding(.trailing, 8)
            }
            // Sağ grup (v1 header-right, gap 8; sağdan sola: settings, git, fullscreen)
            HStack(spacing: 8) {
                HeaderIconButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    isActive: workspace.isFocusMode,
                    action: { workspace.toggleFocusMode() }
                )
                HeaderIconButton(
                    icon: "arrow.triangle.branch",
                    isActive: workspace.rightSidebarOpen,
                    action: { workspace.toggleRightSidebar() }
                )
                HeaderIconButton(
                    icon: "gearshape",
                    isActive: workspace.isSettingsOpen,
                    action: { workspace.isSettingsOpen = true }
                )
            }
        }
        // Sol 80px: traffic light alanı — içerik trafiğin hizasında (v1 paritesi)
        .padding(.leading, 80)
        .padding(.trailing, 16)
        .frame(height: Self.height)
        .background(Theme.bgSurface)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: 1)
        }
    }

    // MARK: - Logo + ad (v1: 26×26 mascot + "Lumi" 14/600)

    private var logoView: some View {
        HStack(spacing: 8) {
            if let logo = LumiAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
            }
            Text("Lumi")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Tab'ler

    /// Tab'ler + (+) butonu tek scroll HStack'inde — (+) her zaman son tab'ın
    /// HEMEN ardında durur (ortada kalmaz); çok tab'da birlikte scroll'lanır.
    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(workspace.openTabs, id: \.self) { repoPath in
                    RepoTabChip(
                        name: repoStore.repo(at: repoPath)?.name
                            ?? (repoPath as NSString).lastPathComponent,
                        isActive: workspace.activeTab == repoPath,
                        onSelect: { workspace.setActiveTab(repoPath) },
                        onClose: { name in
                            workspace.requestCloseTab(repoPath, repoName: name)
                        }
                    )
                }
                addRepoButton
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
    }

    private var addRepoButton: some View {
        Button {
            workspace.isRepoSelectorOpen.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isAddRepoHovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(isAddRepoHovering ? Theme.bgElevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isAddRepoHovering = $0 }
        .popover(isPresented: Binding(
            get: { workspace.isRepoSelectorOpen },
            set: { workspace.isRepoSelectorOpen = $0 }
        )) {
            RepoSelectorView(groups: repoStore.groupedRepos) { repo in
                workspace.isRepoSelectorOpen = false
                workspace.openTab(repo.path)
            }
        }
    }

    private func gridLayoutMenu(for repoPath: String) -> some View {
        GridSettingsControl(
            layout: workspace.gridLayout(for: repoPath),
            onChange: { workspace.setGridLayout($0, for: repoPath) }
        )
    }
}

/// Repo tab'i (v1 globals.css .repo-tab): pasif şeffaf, aktif elevated +
/// accent kenarlık; kapatma butonu yalnız hover'da görünür, hover'ı kırmızı.
struct RepoTabChip: View {
    let name: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (String) -> Void

    @State private var isHovering = false
    @State private var isCloseHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
            Text(name)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 120, alignment: .leading)
            closeButton
                .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .background(isActive ? Theme.bgElevated : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isActive ? Theme.accentVivid.opacity(0.25) : Color.clear,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(isActive ? Theme.accentPrimary : Theme.textSecondary)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }

    private var closeButton: some View {
        Button {
            onClose(name)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isCloseHovering ? Theme.error : Theme.textMuted)
                .frame(width: 18, height: 18)
                .background(isCloseHovering ? Theme.error.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovering = $0 }
    }
}

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

/// Modern "New <Provider>" split-button (v1 paritesi): solid mor; sol kısım
/// aktif provider'ı spawn eder, sağ chevron özel koyu dropdown'u **hover'da**
/// açar (New Bash + persona'lar). Buton VEYA popover üstünde hover olduğu sürece
/// açık kalır; ikisinden de ayrılınca kısa grace period sonra kapanır. Native
/// NSMenu DEĞİL — temalı popover.
struct NewTerminalButton: View {
    static let hoverCloseDelay: Duration = .milliseconds(200)

    let provider: AgentProvider
    let personas: [Persona]
    let onNewProvider: () -> Void
    let onNewBash: () -> Void
    let onPersona: (String) -> Void

    @State private var isOpen = false
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onNewProvider) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("New \(provider.displayName)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 18)

            // Chevron yalnız görsel ipucu — açma/kapama hover'la sürülür.
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .background(Theme.accentVivid)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { updateHover($0) }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            dropdown.onHover { updateHover($0) }
        }
    }

    /// Buton ya da popover hover'ı: girişte aç + bekleyen kapanışı iptal et;
    /// çıkışta grace period zamanlayıcısı kur (arada geçişte flicker olmaz).
    private func updateHover(_ hovering: Bool) {
        if hovering {
            closeTask?.cancel()
            closeTask = nil
            isOpen = true
        } else {
            closeTask?.cancel()
            closeTask = Task { @MainActor in
                try? await Task.sleep(for: Self.hoverCloseDelay)
                guard !Task.isCancelled else { return }
                isOpen = false
            }
        }
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 2) {
            NewTerminalDropdownItem(icon: "terminal", label: "New Bash") {
                isOpen = false
                onNewBash()
            }
            if !personas.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 4)
                ForEach(personas, id: \.id) { persona in
                    NewTerminalDropdownItem(icon: nil, label: "New \(persona.label)") {
                        isOpen = false
                        onPersona(persona.id)
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 220)
        .background(Theme.bgElevated)
    }
}

/// Dropdown satırı — hover'da highlight (v1 dark dropdown paritesi).
private struct NewTerminalDropdownItem: View {
    let icon: String?
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 16)
                }
                Text(label)
                    .font(.system(size: 12, design: .monospaced))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHovering ? Theme.bgSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
