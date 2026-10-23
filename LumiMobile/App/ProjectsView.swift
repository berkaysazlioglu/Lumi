import SwiftUI
import UIKit
import LumiMobileKit

struct ProjectsView: View {
    let model: AppModel
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
    @AppStorage(ProjectsLayoutStyle.storageKey) private var layoutStyle = ProjectsLayoutStyle.default

    var body: some View {
        NavigationStack {
            Group {
                switch layoutStyle {
                case .lumi:
                    LumiProjectsList(model: model, actions: listActions)
                        .navigationBarTitleDisplayMode(.inline)
                        // The title is drawn in the list, under the usage strip (Mac top bar order).
                        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) } }
                case .apple:
                    AppleProjectsList(model: model, actions: listActions)
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(item: $openSession) { sessionId in
                TerminalSessionView(model: model, sessionId: sessionId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { connectionDot }
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
                .lumiThemed()
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


    // MARK: - List actions

    private var listActions: ProjectsListActions {
        ProjectsListActions(
            isOnline: model.macOnline,
            startingPath: startingCheckout,
            open: { openSession = $0 },
            start: { startAgent(at: $0) },
            newBranch: { newBranchPreset = NewBranchPreset(repoPath: $0, baseBranch: $1) },
            delete: { pendingDelete = $0 }
        )
    }

    /// Current-branch start at `path`: the Mac spawns `claude` right there
    /// (checkout, worktree/workspace or a loose folder) — no workspace creation.
    private func startAgent(at path: String) {
        startingCheckout = path
        model.resetStartState()
        Task { await model.startChatSession(repoPath: path) }
    }

    // MARK: - Chrome

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
            Toggle(isOn: Binding(
                get: { layoutStyle == .apple },
                set: { layoutStyle = $0 ? .apple : .lumi }
            )) {
                Label("Apple Layout", systemImage: "list.bullet.rectangle")
            }
            // Apple layout sizes rows with Dynamic Type instead.
            if layoutStyle == .lumi {
                Picker(selection: $rowSize) {
                    ForEach(ProjectsRowSize.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Row Size", systemImage: "list.bullet.indent")
                }
                .pickerStyle(.menu)
            }
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
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                            .foregroundStyle(LumiPalette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.name).font(.body.weight(.medium)).foregroundStyle(LumiPalette.textPrimary)
                            Text(repo.path)
                                .font(.caption).foregroundStyle(LumiPalette.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Image(systemName: "plus.circle").foregroundStyle(LumiPalette.accent)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(LumiPalette.background)
                .listRowSeparatorTint(LumiPalette.border)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(LumiPalette.background)
            .overlay {
                if model.projectsSnapshot.addable.isEmpty {
                    Text("No more projects to add").foregroundStyle(LumiPalette.textSecondary)
                }
            }
            .navigationTitle("Add project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LumiPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // Inside the theme scope so the navy/black/white resolves with the Lumi trait.
        .presentationBackground(LumiPalette.background)
        .lumiThemed()
    }
}

/// Sheet item for the long-press "New branch from …" action.
private struct NewBranchPreset: Identifiable {
    let repoPath: String
    let baseBranch: String
    var id: String { repoPath + "\u{0}" + baseBranch }
}
