import SwiftUI
import LumiMobileKit
import LumiWire

/// A task's detail on the phone: status / assignee pickers, the agent (with
/// Open Chat), and the description fetched on demand (`task_detail`).
struct TaskDetailSheet: View {
    let model: AppModel
    let ref: TaskRef
    let start: () -> Void
    let openChat: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var task: RemoteTask? { model.task(ref) }
    private var source: TaskSourceSummary? { model.taskSource(ref.source) }

    var body: some View {
        NavigationStack {
            Group {
                if let task {
                    form(task)
                } else {
                    ContentUnavailableView("Task removed", systemImage: "trash", description: Text("It no longer exists on the server."))
                }
            }
            .navigationTitle(ref.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { model.loadTaskDetail(ref) }
    }

    private func form(_ task: RemoteTask) -> some View {
        Form {
            Section {
                Text(task.title).font(.title3.weight(.semibold))
                if task.needsAttention {
                    Label("The server sent an unknown status or a broken field.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
            Section {
                Picker(selection: Binding(get: { task.status }, set: { model.moveTask(ref, to: $0) })) {
                    ForEach(RemoteTaskStatus.allCases, id: \.self) { status in
                        Label(status.title, systemImage: TaskStatusGlyph.icon(status)).tag(status)
                    }
                } label: {
                    Label("Status", systemImage: "circle.dashed")
                }
                assignee(task)
                if let priority = task.priority {
                    LabeledContent("Priority") { Text(priority.capitalized) }
                }
                if let project = task.project {
                    LabeledContent("Project") { Text(project.displayName) }
                }
                if !task.labels.isEmpty {
                    LabeledContent("Labels") { Text(task.labels.joined(separator: ", ")) }
                }
                if task.imageCount > 0 {
                    LabeledContent("Images") { Text("\(task.imageCount) — given to the agent on Start") }
                }
            }
            agentSection(task)
            description(task)
            if let url = task.url.flatMap(URL.init(string:)) {
                Section { Link(destination: url) { Label("Open in Browser", systemImage: "safari") } }
            }
        }
    }

    @ViewBuilder
    private func assignee(_ task: RemoteTask) -> some View {
        if let source, source.canAssign {
            Picker(selection: Binding(
                get: { task.assignee?.id ?? "" },
                set: { id in model.assignTask(ref, to: source.assignOptions.first { $0.id == id }) }
            )) {
                ForEach(source.assignOptions) { user in
                    Text(user.id == source.me?.id ? "You (\(user.name))" : user.name).tag(user.id)
                }
                Text("Unassigned").tag("")
            } label: {
                Label("Assignee", systemImage: "person")
            }
        } else if let assignee = task.assignee {
            LabeledContent("Assignee") { Text(assignee.id == source?.me?.id ? "You" : assignee.name) }
        }
    }

    @ViewBuilder
    private func agentSection(_ task: RemoteTask) -> some View {
        Section("Agent") {
            if let agent = task.agent {
                TaskAgentBadge(agent: agent)
                if let checkout = agent.checkout {
                    LabeledContent("Where") { Text(checkout) }
                }
                if let summary = agent.summary {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
                if agent.reattached, agent.state.isActive {
                    Text("Reconnected after Lumi restarted — submit with Move to In Review when it's done.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let terminal = agent.terminalId {
                    Button { openChat(terminal) } label: { Label("Open Chat", systemImage: "bubble.left.and.text.bubble.right") }
                }
                if !agent.state.isActive, task.status != .done {
                    Button { start() } label: { Label("Start Again with Claude", systemImage: "play.fill") }
                }
            } else if task.status != .done {
                Button { start() } label: { Label("Start with Claude", systemImage: "play.fill") }
                    .disabled(!model.macOnline)
            } else {
                Text("No agent").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func description(_ task: RemoteTask) -> some View {
        if task.hasBody {
            Section("Description") {
                if let body = model.detail(for: ref)?.body {
                    Text(Self.markdown(body)).textSelection(.enabled)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
