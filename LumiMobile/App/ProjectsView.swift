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
    /// Checkout whose one-tap agent start is in flight (its + shows a spinner).
    @State private var startingCheckout: String?
    @State private var startError: String?
    /// Long-press "New branch from …" → NewSessionView preset for that checkout.
    @State private var newBranchPreset: NewBranchPreset?
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.default
    @AppStorage(TUIStyle.sizeKey) private var textSize = TUIStyle.defaultSize
    @AppStorage(DemoMode.storageKey) private var demoMode = false
    /// Project whose appearance editor is open (decision 132).
    @State private var editingProject: ProjectNode?

    var body: some View {
        NavigationStack {
            AppleProjectsList(model: model, actions: listActions)
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
            .sheet(item: $editingProject) { project in
                ProjectAppearanceSheet(project: project, isOnline: model.macOnline) { appearance in
                    Task { await model.setProjectAppearance(path: project.path, appearance: appearance) }
                }
            }
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
            .alert("Couldn't update project", isPresented: Binding(
                get: { model.projectEditError != nil },
                set: { if !$0 { model.clearProjectEditError() } }
            )) {
                Button("OK", role: .cancel) { model.clearProjectEditError() }
            } message: {
                Text("Your Mac kept its previous order and look (\(model.projectEditError ?? "")).")
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
            delete: { sessionId in Task { await model.deleteSession(sessionId: sessionId) } },
            edit: { editingProject = $0 },
            move: { path, target in Task { await model.moveProject(path, onto: target) } }
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

/// Sheet item for the long-press "New branch from …" action.
private struct NewBranchPreset: Identifiable {
    let repoPath: String
    let baseBranch: String
    var id: String { repoPath + "\u{0}" + baseBranch }
}
