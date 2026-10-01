import SwiftUI
import LumiMobileKit

struct NewSessionView: View {
    let model: AppModel
    /// Called with the new session id after a successful start, so the
    /// presenter can navigate straight into the agent.
    var onStarted: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var repoPath: String
    @State private var branchMode: String              // current | existing | new (branch mode)
    @State private var selectedBranch = ""
    @State private var newBranchName = ""
    @State private var baseBranch: String
    @State private var workspaceName = ""

    /// Presets let a Projects checkout row open the form as
    /// "new branch from <this checkout's branch>" in the given repo.
    init(model: AppModel, repoPath: String = "", branchMode: String = "current",
         baseBranch: String = "", onStarted: @escaping (String) -> Void = { _ in }) {
        self.model = model
        self.onStarted = onStarted
        _repoPath = State(initialValue: repoPath)
        _branchMode = State(initialValue: branchMode)
        _baseBranch = State(initialValue: baseBranch)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Repo", selection: $repoPath) {
                    Text("Select…").tag("")
                    ForEach(model.repos) { repo in Text(repo.name).tag(repo.path) }
                }
                .onChange(of: repoPath) { _, path in
                    resetBranchFields()
                    if !path.isEmpty { Task { await model.loadBranches(repoPath: path) } }
                }

                if !repoPath.isEmpty {
                    Picker("Branch", selection: $branchMode) {
                        Text("Current branch").tag("current")
                        Text("Existing branch").tag("existing")
                        Text("New branch").tag("new")
                    }
                    .pickerStyle(.segmented)

                    if branchMode == "existing" {
                        if model.branchesLoading {
                            HStack { ProgressView(); Text("Loading branches…") }
                        } else if let err = model.branchesError {
                            Text(err).font(.footnote).foregroundStyle(.orange)
                        } else {
                            Picker("Branch", selection: $selectedBranch) {
                                Text("Select…").tag("")
                                ForEach(model.branchesForRepo, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    } else if branchMode == "new" {
                        TextField("New branch name", text: $newBranchName)
                            .autocorrectionDisabled()
                        Picker("Base branch (opt.)", selection: $baseBranch) {
                            Text("Current branch").tag("")
                            // A preset base may not be in the loaded list (yet) — keep it selectable.
                            if !baseBranch.isEmpty && !model.branchesForRepo.contains(baseBranch) {
                                Text(baseBranch).tag(baseBranch)
                            }
                            ForEach(model.branchesForRepo, id: \.self) { Text($0).tag($0) }
                        }
                    }

                    if branchMode != "current" {
                        TextField("Workspace name (opt.)", text: $workspaceName)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Button(action: submit) {
                        if model.startState == .sending { ProgressView() }
                        else { Text("Start chat") }
                    }
                    .disabled(!canSubmit)
                    if case .failed(let error) = model.startState {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: model.startState) { _, state in
                if state == .succeeded {
                    let sid = model.lastStartedSessionId
                    model.resetStartState()
                    dismiss()
                    if let sid { onStarted(sid) }
                }
            }
            .onAppear {
                model.resetStartState()
                // Preset repo: onChange doesn't fire for the initial value, so load here.
                if !repoPath.isEmpty { Task { await model.loadBranches(repoPath: repoPath) } }
            }
        }
    }

    private var canSubmit: Bool {
        guard model.macOnline, !model.repos.isEmpty, !repoPath.isEmpty,
              model.startState != .sending else { return false }
        switch branchMode {
        case "existing": return !selectedBranch.isEmpty
        case "new": return !newBranchName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private func resetBranchFields() {
        branchMode = "current"; selectedBranch = ""; newBranchName = ""
        baseBranch = ""; workspaceName = ""
    }

    private func submit() {
        Task {
            switch branchMode {
            case "existing":
                await model.startChatSession(repoPath: repoPath, branchMode: "existing",
                    branchName: selectedBranch, workspaceName: workspaceName.isEmpty ? nil : workspaceName)
            case "new":
                await model.startChatSession(repoPath: repoPath, branchMode: "new",
                    branchName: newBranchName, baseBranch: baseBranch.isEmpty ? nil : baseBranch,
                    workspaceName: workspaceName.isEmpty ? nil : workspaceName)
            default:
                await model.startChatSession(repoPath: repoPath)
            }
        }
    }
}
