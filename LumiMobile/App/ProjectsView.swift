import SwiftUI
import UIKit
import LumiMobileKit

struct ProjectsView: View {
    let model: AppModel
    @State private var collapsedProjects: Set<String> = []
    @State private var showAdd = false
    @State private var confirmUnpair = false
    // Single-selection navigation. Replaces per-agent NavigationLink(value:) — when
    // multiple NavigationLinks live in one List cell, SwiftUI activates ALL of them,
    // so tapping one checkout pushed the whole group and Back walked through each chat
    // in sequence. An explicit `navigationDestination(item:)` binding guarantees exactly
    // one push and a clean Back-to-home.
    @State private var openSession: String?
    /// Agent whose deletion is awaiting confirmation (main-screen delete).
    @State private var pendingDelete: String?
    /// Checkout whose one-tap agent start is in flight (its + shows a spinner).
    @State private var startingCheckout: String?
    @State private var startError: String?
    /// Long-press "New branch from …" → NewSessionView preset for that checkout.
    @State private var newBranchPreset: NewBranchPreset?
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.default
    @AppStorage(TUIStyle.sizeKey) private var textSize = TUIStyle.defaultSize
    @AppStorage(DemoMode.storageKey) private var demoMode = false
    @AppStorage(ProjectsRowSize.storageKey) private var rowSize = ProjectsRowSize.default

    /// Project band padding (fixed — it's the anchor of the hierarchy).
    private static let projectRowPadding: CGFloat = 9

    var body: some View {
        NavigationStack {
            List {
                if !model.macOnline { offlineBanner }
                let others = model.otherGroups
                let locations = looseStartLocations(model.projectsSnapshot)
                if model.projectTree.isEmpty { emptyState }
                ForEach(model.projectTree) { project in
                    projectSection(project)
                }
                if !others.isEmpty || !locations.isEmpty { otherSection(others, locations: locations) }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .background(LumiPalette.background)
            .navigationTitle("Projects")
            .navigationDestination(item: $openSession) { sessionId in
                TerminalSessionView(model: model, sessionId: sessionId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        connectionDot
                        // Mac top bar quotas (decision 128).
                        if let usage = model.usage, !usage.isEmpty { UsageIndicators(report: usage) }
                    }
                    .padding(.horizontal, 4)
                    .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!model.macOnline || model.projectsSnapshot.addable.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { settingsMenu }
            }
            .sheet(isPresented: $showAdd) { AddProjectSheet(model: model) }
            .sheet(item: $newBranchPreset) { preset in
                NewSessionView(model: model, repoPath: preset.repoPath, branchMode: "new",
                               baseBranch: preset.baseBranch) { sessionId in
                    openSession = sessionId
                }
            }
            .onChange(of: model.startState) { _, state in
                // Only the one-tap start owns this; the sheet handles its own result.
                guard startingCheckout != nil, newBranchPreset == nil else { return }
                switch state {
                case .succeeded:
                    let sid = model.lastStartedSessionId
                    startingCheckout = nil
                    model.resetStartState()
                    if let sid { openSession = sid }
                case .failed(let error):
                    startingCheckout = nil
                    model.resetStartState()
                    startError = error
                default: break
                }
            }
            .alert("Couldn't start agent", isPresented: Binding(
                get: { startError != nil },
                set: { if !$0 { startError = nil } }
            )) {
                Button("OK", role: .cancel) { startError = nil }
            } message: {
                Text(startError ?? "")
            }
            .confirmationDialog(
                "Disconnect from this Mac?",
                isPresented: $confirmUnpair,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task { await model.unpair() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll return to the pairing screen and can scan a new QR code.")
            }
            .confirmationDialog(
                "Delete this chat?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { sessionId in
                Button("Delete", role: .destructive) {
                    Task { await model.deleteSession(sessionId: sessionId) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { sessionId in
                Text("The \(model.session(sessionId)?.repoName ?? "") session will be ended on the Mac.")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func projectSection(_ project: ProjectRowData) -> some View {
        let collapsed = collapsedProjects.contains(project.id)
        // The header is a plain row (not a Section header): plain-list headers
        // carry their own system fill that ignores the Lumi surface.
        sectionHeader(id: project.id, collapsed: collapsed) {
            ProjectIconView(icon: project.node.appearance.icon)
            Text(project.node.name).font(.headline).foregroundStyle(LumiPalette.textPrimary)
            if let color = project.node.appearance.color { ProjectColorDot(color: color) }
        }
        .treeRow(.project, verticalPadding: Self.projectRowPadding)
        if !collapsed {
            // Agents are emitted as their own List rows (not nested inside a single
            // checkout cell) so each is individually selectable and supports swipe /
            // long-press delete.
            ForEach(project.checkouts) { checkout in
                checkoutHeader(checkout, in: project)
                ForEach(checkout.agents) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    private func sectionHeader<Label: View>(id: String, collapsed: Bool,
                                            @ViewBuilder label: () -> Label) -> some View {
        Button {
            if !collapsedProjects.insert(id).inserted { collapsedProjects.remove(id) }
        } label: {
            HStack(spacing: 8) {
                label()
                Spacer()
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption).foregroundStyle(LumiPalette.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Projects ▸ Other (Mac decision 108): terminals opened outside any project,
    /// grouped by folder. `+` opens a new Claude in one of the Mac's locations
    /// (home, roots) or next to existing loose terminals.
    @ViewBuilder
    private func otherSection(_ groups: [OtherGroupRowData], locations: [LooseLocation]) -> some View {
        let collapsed = collapsedProjects.contains(Self.otherSectionID)
        HStack(spacing: 8) {
            sectionHeader(id: Self.otherSectionID, collapsed: collapsed) {
                Image(systemName: "tray").font(.headline).foregroundStyle(LumiPalette.textSecondary)
                Text("Other").font(.headline).foregroundStyle(LumiPalette.textPrimary)
            }
            looseStartMenu(locations)
        }
        .treeRow(.project, verticalPadding: Self.projectRowPadding)
        if !collapsed {
            ForEach(groups) { group in
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.caption).foregroundStyle(LumiPalette.textSecondary)
                    Text(group.node.label).font(rowSize.checkoutFont)
                        .foregroundStyle(LumiPalette.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    startButton(id: group.id, label: "New Claude in \(group.node.label)") {
                        startAgent(at: group.node.path)
                    }
                }
                .treeRow(.checkout, verticalPadding: rowSize.verticalPadding)
                ForEach(group.agents) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    /// `+` of the Other header: pick the folder for a new loose Claude.
    @ViewBuilder
    private func looseStartMenu(_ locations: [LooseLocation]) -> some View {
        if let busy = startingCheckout, locations.contains(where: { $0.path == busy }) {
            ProgressView().controlSize(.small).frame(width: 28, height: 24)
        } else {
            Menu {
                Section("New Claude in…") {
                    ForEach(locations) { location in
                        Button { startAgent(at: location.path) } label: {
                            Label(location.label, systemImage: location.label == "~" ? "house" : "folder")
                        }
                    }
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!model.macOnline || startingCheckout != nil || locations.isEmpty)
            .accessibilityLabel("New Claude outside a project")
        }
    }

    /// Collapse key for the Other section; NUL keeps it apart from project paths.
    private static let otherSectionID = "\u{0}other"

    @ViewBuilder
    private func checkoutHeader(_ checkout: CheckoutRowData, in project: ProjectRowData) -> some View {
        HStack(spacing: 8) {
            // "workspace" kind → branch icon; "original" (main checkout) → house icon
            Image(systemName: checkout.node.kind == "workspace" ? "arrow.triangle.branch" : "house")
                .font(.caption).foregroundStyle(LumiPalette.textSecondary)
            Text(checkoutDisplayTitle(checkout.node, in: project.node)).font(rowSize.checkoutFont)
                .foregroundStyle(LumiPalette.textPrimary)
            if let branch = checkout.node.branch, !branch.isEmpty {
                Text(branch)
                    .font(.caption).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            newAgentButton(checkout, in: project)
        }
        .treeRow(.checkout, verticalPadding: rowSize.verticalPadding)
    }

    /// Tap: start a Claude agent right in this checkout's folder and open it.
    /// Long-press: menu that also offers creating a new branch from this one.
    @ViewBuilder
    private func newAgentButton(_ checkout: CheckoutRowData, in project: ProjectRowData) -> some View {
        let branch = checkout.node.branch.flatMap { $0.isEmpty ? nil : $0 }
        if startingCheckout == checkout.id {
            ProgressView().controlSize(.small).frame(width: 28, height: 24)
        } else {
            Menu {
                Button { startAgent(in: checkout) } label: {
                    Label("New Claude on \(branch ?? checkout.node.title)", systemImage: "sparkle")
                }
                Button {
                    newBranchPreset = NewBranchPreset(repoPath: project.node.path, baseBranch: branch ?? "")
                } label: {
                    Label("New branch from \(branch ?? "current")…", systemImage: "arrow.triangle.branch")
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            } primaryAction: {
                startAgent(in: checkout)
            }
            .buttonStyle(.borderless)
            .disabled(!model.macOnline || startingCheckout != nil)
            .accessibilityLabel("New agent on \(branch ?? checkout.node.title)")
        }
    }

    private func startAgent(in checkout: CheckoutRowData) {
        startAgent(at: checkout.node.path)
    }

    /// Current-branch start at `path`: the Mac spawns `claude` right there
    /// (checkout, worktree/workspace or a loose folder) — no workspace creation.
    private func startAgent(at path: String) {
        startingCheckout = path
        model.resetStartState()
        Task { await model.startChatSession(repoPath: path) }
    }

    /// `+` that starts a Claude right away (spinner while in flight).
    @ViewBuilder
    private func startButton(id: String, label: String, action: @escaping () -> Void) -> some View {
        if startingCheckout == id {
            ProgressView().controlSize(.small).frame(width: 28, height: 24)
        } else {
            Button(action: action) {
                Image(systemName: "plus.circle")
                    .font(.body)
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!model.macOnline || startingCheckout != nil)
            .accessibilityLabel(label)
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentRowData) -> some View {
        Button {
            openSession = agent.id
        } label: {
            HStack(spacing: 8) {
                AgentActivityGlyph(activity: agent.activity)
                Image(systemName: providerSymbol(agent.provider))
                    .font(rowSize.agentFont).foregroundStyle(LumiPalette.textSecondary)
                Text(agent.title)
                    .font(rowSize.agentFont)
                    .foregroundStyle(agent.needsAttention ? Color.orange : LumiPalette.textPrimary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                if agent.activity == .running || agent.activity == .awaitingDecision {
                    Text(agent.activity.title)
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
                Text(PhoneRelativeTime.shortLabel(
                    agent.lastActivityAt,
                    now: Date().timeIntervalSince1970 * 1000
                ))
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                if agent.needsAttention {
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange).frame(width: 3)
                        .offset(x: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .treeRow(.agent, verticalPadding: rowSize.verticalPadding)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = agent.id } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) { pendingDelete = agent.id } label: {
                Label("Delete this chat", systemImage: "trash")
            }
        }
    }

    private func providerSymbol(_ provider: String?) -> String {
        switch provider {
        case "claude": "sparkle"
        case "codex": "chevron.left.forwardslash.chevron.right"
        default: "circle.fill"
        }
    }

    // MARK: - Chrome

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus").font(.title).foregroundStyle(.secondary)
            Text("No projects yet").foregroundStyle(.secondary)
            Text("Add a project on the Mac, or use +").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
        .lumiRow()
    }

    private var offlineBanner: some View {
        Label("Mac offline", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            .font(.callout).foregroundStyle(.orange)
            .lumiRow()
    }

    private var connectionDot: some View {
        Circle()
            .fill(model.connection == .connected ? .green :
                  model.connection == .connecting ? .yellow : .red)
            .frame(width: 10, height: 10)
            .accessibilityLabel("Relay connection")
    }

    // Always reachable — even while offline or stuck on a stale pairing —
    // so a dead relay connection can be recovered by disconnecting and
    // re-pairing. (Ported from the retired SessionListView gear menu.)
    private var settingsMenu: some View {
        Menu {
            Toggle("Notifications", isOn: Binding(
                get: { model.notificationsEnabled },
                set: { isOn in
                    Task {
                        if isOn {
                            if await model.enableNotifications() == .needsSettings,
                               let url = URL(string: UIApplication.openSettingsURLString) {
                                await UIApplication.shared.open(url)
                            }
                        } else {
                            await model.disableNotifications()
                        }
                    }
                }
            ))
            Picker(selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
            Picker(selection: $textSize) {
                ForEach(Int(TUIStyle.sizeRange.lowerBound)...Int(TUIStyle.sizeRange.upperBound), id: \.self) {
                    Text("\($0) pt").tag(Double($0))
                }
            } label: {
                Label("Text Size", systemImage: "textformat.size")
            }
            .pickerStyle(.menu)
            Picker(selection: $rowSize) {
                ForEach(ProjectsRowSize.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Row Size", systemImage: "list.bullet.indent")
            }
            .pickerStyle(.menu)
            if demoMode {
                Button("Exit Demo Data", role: .destructive) { demoMode = false }
            } else {
                Button("Disconnect", role: .destructive) { confirmUnpair = true }
            }
        } label: {
            Image(systemName: "gearshape")
        }
    }
}

private struct AddProjectSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.projectsSnapshot.addable) { repo in
                Button {
                    Task { await model.addProject(path: repo.path) }
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(repo.name).foregroundStyle(.primary)
                            Text(repo.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            .overlay {
                if model.projectsSnapshot.addable.isEmpty {
                    Text("No more projects to add").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Sheet item for the long-press "New branch from …" action.
private struct NewBranchPreset: Identifiable {
    let repoPath: String
    let baseBranch: String
    var id: String { repoPath + "\u{0}" + baseBranch }
}
