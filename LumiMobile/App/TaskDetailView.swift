import SwiftUI
import LumiMobileKit
import LumiWire

/// A task's detail on the phone, pushed full screen from the board: the title
/// with its status, the properties (status / assignee menus), the agent with
/// Start / Open Chat, and the description fetched on demand (`task_detail`).
/// Start is this screen's own sheet and its chat is pushed on top of it, so
/// Back from the chat lands here again.
struct TaskDetailView: View {
    let model: AppModel
    let ref: TaskRef

    @State private var starting = false
    /// Chat to push once the Start sheet is gone (a push mid-dismiss is dropped).
    @State private var pendingChat: String?
    @State private var chat: String?

    private var task: RemoteTask? { model.task(ref) }
    private var source: TaskSourceSummary? { model.taskSource(ref.source) }

    var body: some View {
        Group {
            if let task {
                content(task)
            } else {
                ContentUnavailableView("Task removed", systemImage: "trash",
                                       description: Text("It no longer exists on the server."))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(ref.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let task { ToolbarItem(placement: .topBarTrailing) { moreMenu(task) } }
        }
        .onAppear { model.loadTaskDetail(ref) }
        .sheet(isPresented: $starting, onDismiss: {
            chat = pendingChat
            pendingChat = nil
        }) {
            TaskStartSheet(model: model, ref: ref) { sessionId in
                pendingChat = sessionId
                starting = false
            }
            .lumiThemed()
        }
        .navigationDestination(item: $chat) { sessionId in
            TerminalSessionView(model: model, sessionId: sessionId)
        }
    }

    private func content(_ task: RemoteTask) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaskDetailMetrics.sectionSpacing) {
                header(task)
                TaskDetailCard { properties(task) }
                agentCard(task)
                description(task)
                if let url = task.url.flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        Label("Open in Browser", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, TaskDetailMetrics.gutter)
            .padding(.vertical, TaskDetailMetrics.sectionSpacing)
        }
    }

    // MARK: - Header

    private func header(_ task: RemoteTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TaskStatusPill(status: task.status)
                if let priority = task.priority, priority != "none" {
                    TaskPriorityPill(priority: priority)
                }
                Spacer(minLength: 0)
                if let updated = TaskDates.relative(task.updatedAt) {
                    Text(updated).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(task.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            if task.needsAttention {
                Label("The server sent an unknown status or a broken field.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if !task.labels.isEmpty {
                TaskLabelChips(labels: task.labels)
            }
        }
    }

    // MARK: - Properties

    @ViewBuilder
    private func properties(_ task: RemoteTask) -> some View {
        TaskPropertyRow("Status", icon: "circle.dashed") {
            Menu {
                Picker("Status", selection: Binding(get: { task.status }, set: { model.moveTask(ref, to: $0) })) {
                    ForEach(RemoteTaskStatus.allCases, id: \.self) { status in
                        Label(status.title, systemImage: TaskStatusGlyph.icon(status)).tag(status)
                    }
                }
            } label: {
                TaskMenuLabel { TaskStatusGlyph(status: task.status); Text(task.status.title) }
            }
        }
        Divider()
        TaskPropertyRow("Assignee", icon: "person") { assignee(task) }
        if let project = task.project {
            Divider()
            TaskPropertyRow("Project", icon: "folder") { Text(project.displayName).foregroundStyle(.secondary) }
        }
        if let source, model.taskSources.count > 1 {
            Divider()
            TaskPropertyRow("Source", icon: "tray.full") { Text(source.name).foregroundStyle(.secondary) }
        }
        if task.imageCount > 0 {
            Divider()
            TaskPropertyRow("Images", icon: "photo.on.rectangle") {
                Text("\(task.imageCount) · given to the agent").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func assignee(_ task: RemoteTask) -> some View {
        let name = task.assignee.map { $0.id == source?.me?.id ? "You" : $0.name }
        if let source, source.canAssign {
            Menu {
                Picker("Assignee", selection: Binding(
                    get: { task.assignee?.id ?? "" },
                    set: { id in model.assignTask(ref, to: source.assignOptions.first { $0.id == id }) }
                )) {
                    ForEach(source.assignOptions) { user in
                        Text(user.id == source.me?.id ? "You (\(user.name))" : user.name).tag(user.id)
                    }
                    Text("Unassigned").tag("")
                }
            } label: {
                TaskMenuLabel { assigneeLabel(task, name: name) }
            }
        } else {
            assigneeLabel(task, name: name).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func assigneeLabel(_ task: RemoteTask, name: String?) -> some View {
        if let assignee = task.assignee {
            TaskAvatarView(user: assignee, isMe: assignee.id == source?.me?.id)
        }
        Text(name ?? "Unassigned")
    }

    // MARK: - Agent

    private func agentCard(_ task: RemoteTask) -> some View {
        TaskDetailCard(title: "Agent") {
            if let agent = task.agent {
                HStack {
                    TaskAgentBadge(agent: agent)
                    Spacer(minLength: 0)
                }
                if let checkout = agent.checkout {
                    Label(checkout, systemImage: "arrow.triangle.branch")
                        .font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                if let summary = agent.summary {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
                if agent.reattached, agent.state.isActive {
                    Text("Reconnected after Lumi restarted — submit with Move to In Review when it's done.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                if let terminal = agent.terminalId {
                    primaryButton("Open Chat", icon: "bubble.left.and.text.bubble.right") { chat = terminal }
                }
                if !agent.state.isActive, task.status != .done {
                    Button { starting = true } label: {
                        Label("Start Again with Claude", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!model.macOnline)
                }
            } else if task.status != .done {
                Text("Claude works on it in its own workspace and moves it to In Review when it's done.")
                    .font(.footnote).foregroundStyle(.secondary)
                primaryButton("Start with Claude", icon: "play.fill") { starting = true }
                    .disabled(!model.macOnline)
            } else {
                Text("No agent").foregroundStyle(.secondary)
            }
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.body.weight(.semibold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Description

    @ViewBuilder
    private func description(_ task: RemoteTask) -> some View {
        if task.hasBody {
            TaskDetailCard(title: "Description") {
                if let body = model.detail(for: ref)?.body {
                    Text(Self.markdown(body))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Toolbar

    private func moreMenu(_ task: RemoteTask) -> some View {
        Menu {
            Menu("Move to") {
                ForEach(RemoteTaskStatus.allCases, id: \.self) { status in
                    Button { model.moveTask(ref, to: status) } label: {
                        Label(status.title, systemImage: TaskStatusGlyph.icon(status))
                    }
                    .disabled(status == task.status)
                }
            }
            if let source, source.canAssign, let me = source.me, task.assignee?.id != me.id {
                Button { model.assignTask(ref, to: me) } label: {
                    Label("Assign to Me", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            if let url = task.url {
                Button { UIPasteboard.general.string = url } label: { Label("Copy Link", systemImage: "link") }
            }
            Button { UIPasteboard.general.string = task.id } label: { Label("Copy ID", systemImage: "number") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

enum TaskDetailMetrics {
    static let gutter: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 14
    static let propertyLabelWidth: CGFloat = 104
}

/// A rounded group on the detail screen, optionally titled like a list section.
private struct TaskDetailCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, TaskDetailMetrics.cardPadding)
            }
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(TaskDetailMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: TaskDetailMetrics.cardRadius, style: .continuous))
        }
    }
}

/// `◌ Status        ● In Progress ⌄` — label on the left, value on the right.
private struct TaskPropertyRow<Value: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let value: Value

    init(_ title: String, icon: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.icon = icon
        self.value = value()
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
                .frame(width: TaskDetailMetrics.propertyLabelWidth, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 6) { value }
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

/// A menu's value with a chevron, so it reads as tappable.
private struct TaskMenuLabel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            content
            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
    }
}

/// Labels as small chips (scroll sideways when long).
private struct TaskLabelChips: View {
    let labels: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
        }
    }
}
