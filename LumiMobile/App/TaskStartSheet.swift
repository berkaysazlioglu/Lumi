import SwiftUI
import LumiMobileKit
import LumiWire

/// Start with Claude from the phone: the Mac does the work (project match,
/// task workspace, the source's prompt template, images). The phone picks
/// the model, optionally the project, and where the agent runs. When the
/// agent's terminal appears, its chat opens.
struct TaskStartSheet: View {
    let model: AppModel
    let ref: TaskRef
    /// Called when done: the agent's session id to open, or nil.
    let finish: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    /// "" = let the Mac match the task's project.
    @State private var projectPath = ""
    @State private var existingCheckout = false
    @State private var alias: ClaudeModelAlias?
    @State private var waitingForTerminal = false

    private var task: RemoteTask? { model.task(ref) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task?.title ?? ref.id).font(.headline)
                }
                Section {
                    Picker("Project", selection: $projectPath) {
                        Text("Match on Mac").tag("")
                        ForEach(model.projectTree) { project in
                            Text(project.node.name).tag(project.node.path)
                        }
                    }
                    Picker("Where", selection: $existingCheckout) {
                        Text("New workspace").tag(false)
                        Text("Project folder").tag(true)
                    }
                    Picker("Model", selection: $alias) {
                        Text("Default").tag(ClaudeModelAlias?.none)
                        ForEach(ClaudeModelAlias.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                    }
                } footer: {
                    Text("A new workspace is a git worktree on a task/… branch, so parallel tasks don't touch each other. Non-git projects run in the project folder.")
                }
                if case .failed(let message, let needsProject) = model.taskStartState {
                    Section {
                        Label(message, systemImage: needsProject ? "folder.badge.questionmark" : "exclamationmark.triangle")
                            .foregroundStyle(needsProject ? .orange : .red)
                    }
                }
                if let prompt = model.detail(for: ref)?.prompt {
                    Section {
                        Text(prompt).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    } header: {
                        Text("Prompt")
                    } footer: {
                        Text("Wrapped with this source's prompt template — edit it in Lumi on your Mac.")
                    }
                }
            }
            .navigationTitle("Start with Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.resetTaskStart(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.taskStartState == .sending || waitingForTerminal {
                        ProgressView()
                    } else {
                        Button("Start") {
                            model.startTask(ref, model: alias, projectPath: projectPath.isEmpty ? nil : projectPath,
                                            existingCheckout: existingCheckout)
                        }
                        .disabled(!model.macOnline)
                    }
                }
            }
        }
        .onAppear {
            model.resetTaskStart()
            if model.detail(for: ref) == nil { model.loadTaskDetail(ref) }
        }
        .onChange(of: model.taskStartState) { _, state in
            guard state == .succeeded else { return }
            model.resetTaskStart()
            waitingForTerminal = true
        }
        // The Mac publishes the agent's terminal a moment after Start (a new
        // workspace takes longer) — open its chat as soon as it's there.
        .onChange(of: task?.agent?.terminalId) { _, terminal in
            guard waitingForTerminal, let terminal else { return }
            waitingForTerminal = false
            finish(terminal)
        }
        .task(id: waitingForTerminal) {
            guard waitingForTerminal else { return }
            try? await Task.sleep(for: .seconds(20))
            if waitingForTerminal { waitingForTerminal = false; finish(nil) }
        }
    }
}
