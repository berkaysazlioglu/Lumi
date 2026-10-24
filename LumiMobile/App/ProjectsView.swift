import SwiftUI
import UIKit
import LumiMobileKit
import LumiWire

struct ProjectsView: View {
    let model: AppModel
    @State private var showAdd = false
    @State private var showSettings = false
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
    /// Project whose appearance editor is open (decision 132).
    @State private var editingProject: ProjectNode?
    /// Projects | Tasks (Mac decision 137, mobile addendum); survives relaunches.
    @AppStorage("homeMode") private var mode: HomeMode = .projects

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .projects:
                    AppleProjectsList(model: model, actions: listActions)
                        .navigationTitle("Projects")
                case .tasks:
                    TasksView(model: model, openSession: { openSession = $0 })
                        .navigationTitle("Tasks")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $openSession) { sessionId in
                TerminalSessionView(model: model, sessionId: sessionId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { connectionDot }
                ToolbarItem(placement: .principal) { modePicker }
                if mode == .projects {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAdd = true } label: { Image(systemName: "plus") }
                            .disabled(!model.macOnline || model.projectsSnapshot.addable.isEmpty)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { settingsButton }
            }
            .sheet(isPresented: $showAdd) { AddProjectSheet(model: model) }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
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
        }
    }


    // MARK: - List actions

    private var listActions: ProjectsListActions {
        ProjectsListActions(
            isOnline: model.macOnline,
            startingPath: startingCheckout,
            open: { openSession = $0 },
            start: { startAgent(at: $0, model: $1) },
            newBranch: { newBranchPreset = NewBranchPreset(repoPath: $0, baseBranch: $1) },
            delete: { sessionId in Task { await model.deleteSession(sessionId: sessionId) } },
            edit: { editingProject = $0 },
            move: { path, target in Task { await model.moveProject(path, onto: target) } }
        )
    }

    /// Current-branch start at `path`: the Mac spawns `claude` right there
    /// (checkout, worktree/workspace or a loose folder) — no workspace creation.
    private func startAgent(at path: String, model alias: ClaudeModelAlias?) {
        startingCheckout = path
        model.resetStartState()
        Task { await model.startChatSession(repoPath: path, model: alias) }
    }

    // MARK: - Chrome

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(HomeMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    private var connectionDot: some View {
        Circle()
            .fill(model.connection == .connected ? .green :
                  model.connection == .connecting ? .yellow : .red)
            .frame(width: 10, height: 10)
            .accessibilityLabel("Relay connection")
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel("Settings")
    }
}

/// The home screen's two views.
enum HomeMode: String, CaseIterable {
    case projects
    case tasks

    var title: String {
        switch self {
        case .projects: "Projects"
        case .tasks: "Tasks"
        }
    }
}

/// Sheet item for the long-press "New branch from …" action.
private struct NewBranchPreset: Identifiable {
    let repoPath: String
    let baseBranch: String
    var id: String { repoPath + "\u{0}" + baseBranch }
}
