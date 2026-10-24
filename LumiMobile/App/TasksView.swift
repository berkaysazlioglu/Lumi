import SwiftUI
import LumiMobileKit
import LumiWire

/// The Tasks board on the phone (Mac decision 137, mobile addendum): the Mac's
/// board seen through the relay. Visible ⇒ a viewer lease keeps the Mac
/// refreshing; left ⇒ released (no server requests when nobody looks).
struct TasksView: View {
    let model: AppModel
    /// Opens an agent's chat (its terminal id is the phone's session id).
    let openSession: (String) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tasksSource") private var sourceFilter = ""
    @AppStorage("tasksShowDone") private var showDone = false
    @AppStorage("tasksMineOnly") private var mineOnly = false
    @State private var selected: TaskSheetItem?
    @State private var starting: TaskSheetItem?
    @State private var creating = false
    @State private var newTitle = ""

    private var statuses: Set<RemoteTaskStatus> {
        showDone ? Set(RemoteTaskStatus.allCases) : [.todo, .inProgress, .inReview]
    }

    private var activeSource: String? {
        model.taskSources.contains { $0.id == sourceFilter } ? sourceFilter : nil
    }

    private var sections: [TaskList.Section] {
        TaskList.sections(model.displayedTasks, source: activeSource, statuses: statuses, mineOnly: mineOnly) {
            model.taskSource($0)?.me?.id
        }
    }

    private var creatableSource: TaskSourceSummary? {
        let candidates = model.taskSources.filter(\.canCreate)
        return candidates.first { $0.id == activeSource } ?? (activeSource == nil ? candidates.first : nil)
    }

    var body: some View {
        List {
            filters
            ForEach(model.taskSources.filter { activeSource == nil || $0.id == activeSource }) { source in
                if let banner = TaskSourceBanner(source: source) { banner }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.tasks) { task in
                        row(task)
                    }
                } header: {
                    HStack(spacing: 6) {
                        TaskStatusGlyph(status: section.status)
                        Text(section.status.title)
                        Text("\(section.tasks.count)").foregroundStyle(.secondary)
                    }
                }
            }
            if showDone, let truncated = model.tasksSnapshot?.truncatedDone, truncated > 0 {
                Text("\(truncated) older Done tasks are only on your Mac.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .overlay { emptyState }
        .refreshable { model.setTasksVisible(false); model.setTasksVisible(true) }
        .toolbar {
            if creatableSource != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newTitle = ""; creating = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New task")
                        .disabled(!model.macOnline)
                }
            }
        }
        .onAppear { model.setTasksVisible(true) }
        .onDisappear { model.setTasksVisible(false) }
        .onChange(of: scenePhase) { _, phase in model.setTasksVisible(phase == .active) }
        .sheet(item: $selected) { item in
            TaskDetailSheet(model: model, ref: item.ref, start: { starting = item }, openChat: { id in
                selected = nil
                openSession(id)
            })
            .lumiThemed()
        }
        .sheet(item: $starting) { item in
            TaskStartSheet(model: model, ref: item.ref) { sessionId in
                starting = nil
                selected = nil
                if let sessionId { openSession(sessionId) }
            }
            .lumiThemed()
        }
        .alert("New Task", isPresented: $creating) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let source = creatableSource { model.createTask(source: source.id, title: newTitle) }
            }
        } message: {
            if let source = creatableSource { Text("Added to \(source.name) as Todo.") }
        }
        .alert("Couldn't update task", isPresented: Binding(
            get: { model.taskError != nil },
            set: { if !$0 { model.clearTaskError() } }
        )) {
            Button("OK", role: .cancel) { model.clearTaskError() }
        } message: {
            Text(model.taskError ?? "")
        }
    }

    // MARK: - Filters

    private var filters: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.taskSources.count > 1 {
                        Menu {
                            Picker("Source", selection: $sourceFilter) {
                                Text("All Sources").tag("")
                                ForEach(model.taskSources) { Text($0.name).tag($0.id) }
                            }
                        } label: {
                            chip(model.taskSource(sourceFilter)?.name ?? "All Sources", icon: "tray.full", isOn: activeSource != nil)
                        }
                    }
                    Button { mineOnly.toggle() } label: { chip("Mine", icon: "person", isOn: mineOnly) }
                    Button { showDone.toggle() } label: { chip("Done", icon: "checkmark.circle", isOn: showDone) }
                    if let updated = freshness {
                        Text(updated).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private var freshness: String? {
        let stamps = model.taskSources.compactMap(\.lastUpdated)
        guard let oldest = stamps.min() else { return nil }
        let date = Date(timeIntervalSince1970: oldest / 1000)
        return "Updated " + date.formatted(.relative(presentation: .named))
    }

    private func chip(_ title: String, icon: String, isOn: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? LumiPalette.accent.opacity(0.2) : LumiPalette.elevated, in: Capsule())
            .foregroundStyle(isOn ? LumiPalette.accent : .primary)
    }

    // MARK: - Rows

    private func row(_ task: RemoteTask) -> some View {
        let source = model.taskSource(task.source)
        return Button { selected = TaskSheetItem(ref: task.key) } label: {
            TaskRowView(task: task, me: source?.me, showsSource: activeSource == nil && model.taskSources.count > 1, sourceName: source?.name)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let next = task.status.next {
                Button { model.moveTask(task.key, to: next) } label: {
                    Label(next.title, systemImage: TaskStatusGlyph.icon(next))
                }
                .tint(TaskStatusGlyph.color(next))
            }
        }
        .swipeActions(edge: .trailing) {
            if let terminal = task.agent?.terminalId, task.agent?.state.isActive == true {
                Button { openSession(terminal) } label: { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
                    .tint(LumiPalette.accent)
            } else if task.status != .done {
                Button { starting = TaskSheetItem(ref: task.key) } label: { Label("Start", systemImage: "play.fill") }
                    .tint(LumiPalette.accent)
            }
        }
        .contextMenu { menu(task, source: source) }
    }

    @ViewBuilder
    private func menu(_ task: RemoteTask, source: TaskSourceSummary?) -> some View {
        Menu("Move to") {
            ForEach(RemoteTaskStatus.allCases, id: \.self) { status in
                Button { model.moveTask(task.key, to: status) } label: {
                    Label(status.title, systemImage: TaskStatusGlyph.icon(status))
                }
                .disabled(status == task.status)
            }
        }
        if let source, source.canAssign, let me = source.me, task.assignee?.id != me.id {
            Button { model.assignTask(task.key, to: me) } label: { Label("Assign to Me", systemImage: "person.crop.circle.badge.checkmark") }
        }
        if let terminal = task.agent?.terminalId {
            Button { openSession(terminal) } label: { Label("Open Chat", systemImage: "bubble.left.and.text.bubble.right") }
        }
        if task.agent?.state.isActive != true, task.status != .done {
            Button { starting = TaskSheetItem(ref: task.key) } label: { Label("Start with Claude", systemImage: "play.fill") }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.tasksSnapshot == nil || model.taskSources.isEmpty {
            ContentUnavailableView(
                "No task sources",
                systemImage: "checklist",
                description: Text(model.macOnline
                    ? "Connect a task source in Lumi on your Mac (Tasks ▸ Connect Task Source)."
                    : "Your Mac is offline. Tasks appear here once it's back.")
            )
        } else if sections.isEmpty {
            ContentUnavailableView("Nothing here", systemImage: "checkmark.circle",
                                   description: Text(mineOnly ? "No open tasks are assigned to you." : "No open tasks."))
        }
    }
}

struct TaskSheetItem: Identifiable {
    let ref: TaskRef
    var id: String { ref.identity }
}

/// A source that can't be read right now — fixed on the Mac, where its token lives.
private struct TaskSourceBanner: View {
    let source: TaskSourceSummary
    private let text: String
    private let color: Color

    init?(source: TaskSourceSummary) {
        self.source = source
        switch source.phase {
        case .ready, .loading: return nil
        case .offline: (text, color) = ("\(source.name) is offline. Showing the last list.", .orange)
        case .failing: (text, color) = ("\(source.name) answered with an error. Details are in Lumi on your Mac.", .red)
        case .reconnect: (text, color) = ("\(source.name) rejected its token. Reconnect it in Lumi on your Mac.", .red)
        case .unsupported: (text, color) = ("\(source.name): \(source.phaseMessage ?? "unsupported")", .red)
        }
    }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(color)
    }
}
