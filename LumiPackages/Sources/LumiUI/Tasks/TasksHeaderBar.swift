import LumiKit
import LumiState
import SwiftUI

/// Tasks route'unun kendi başlık şeridi: kaynak, arama, filtreler, görünüm,
/// tazelik ve `New Task`. Filtreler yalnız görünen kaynaklardan biri o alanı
/// okuyabiliyorsa çıkar.
struct TasksHeaderBar: View {
    @Bindable var store: TasksStore

    private static var searchWidth: CGFloat { Theme.scaled(200) }
    private static var layoutSwitchWidth: CGFloat { Theme.scaled(130) }
    private static let tickSeconds: TimeInterval = 5

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            sourceMenu
            LumiTextInput(text: $store.filter.query, placeholder: "Search tasks", width: Self.searchWidth)
            if store.anyVisibleSourceCanRead(.project), !store.knownProjects.isEmpty {
                projectFilter
            }
            if store.anyVisibleSourceCanRead(.assignee) {
                assigneeFilter
            }
            if store.filter.isActive {
                Button("Clear") {
                    store.filter = TaskFilter(source: store.filter.source)
                }
                .buttonStyle(HoverButtonStyle(foreground: Theme.textMuted))
                .font(Theme.Typography.labelMono)
            }
            Spacer(minLength: Theme.Spacing.md)
            freshness
            SegmentedModeSwitch(
                options: TasksStore.Layout.allCases,
                selection: $store.layout,
                title: \.title,
                accessibilityLabel: "Layout"
            )
            .frame(width: Self.layoutSwitchWidth)
            if !store.creatableSources.isEmpty {
                LumiActionButton(title: "New Task", kind: .primary) { store.beginNewTask() }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.bgSurface)
    }

    // MARK: - Kaynak

    private var selectedState: TasksStore.SourceState? {
        store.filter.source.flatMap { store.state(of: $0) }
    }

    private var sourceMenu: some View {
        TaskMenuButton(items: sourceItems) {
            Image(systemName: "tray.full")
                .font(Theme.Typography.ui(.label))
                .accessibilityHidden(true)
            Text(selectedState?.source.name ?? (store.sources.count > 1 ? "All Sources" : store.sources.first?.source.name ?? "Tasks"))
                .font(Theme.Typography.mono(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }

    private func sourceItems() -> [PopoverMenu.Item] {
        var items: [PopoverMenu.Item] = []
        if store.sources.count > 1 {
            items.append(.toggle("All Sources", isOn: store.filter.source == nil) { store.filter.source = nil })
            for state in store.sources {
                items.append(.toggle(state.source.name, isOn: store.filter.source == state.id) {
                    store.filter.source = state.id
                })
            }
            items.append(.divider)
        }
        items.append(.action("Connect Task Source…", icon: "plus") { store.beginConnect() })
        let target = selectedState ?? (store.sources.count == 1 ? store.sources.first : nil)
        if let target {
            if target.source.kind == .demo {
                items.append(.submenu("Simulate Missing", icon: "slider.horizontal.3", items: demoToggles(target)))
            }
            items.append(.divider)
            items.append(.action("Disconnect \(target.source.name)", icon: "xmark.circle", isDestructive: true) {
                store.removeSource(target.id)
            })
        }
        return items
    }

    /// Demo kaynağın beyanını maskeleyen anahtarlar: işaretli = kaynakta var.
    private func demoToggles(_ state: TasksStore.SourceState) -> [PopoverMenu.Item] {
        var items: [PopoverMenu.Item] = [.section("Capabilities")]
        for capability in TaskCapability.allCases where state.declaredCapabilities.contains(capability) {
            let isOn = !state.hiddenCapabilities.contains(capability)
            items.append(.toggle(capability.title, isOn: isOn) {
                store.setCapability(capability, hidden: isOn, in: state.id)
            })
        }
        items.append(.section("Fields"))
        for field in TaskField.allCases where state.declaredFields.contains(field) {
            let isOn = !state.hiddenFields.contains(field)
            items.append(.toggle(field.title, isOn: isOn) {
                store.setField(field, hidden: isOn, in: state.id)
            })
        }
        return items
    }

    // MARK: - Filtreler

    private var projectFilter: some View {
        let selected = store.knownProjects.first { $0.key == store.filter.projectKey }
        return TaskMenuButton(items: {
            var items: [PopoverMenu.Item] = [
                .toggle("All Projects", isOn: store.filter.projectKey == nil) { store.filter.projectKey = nil },
                .divider,
            ]
            for project in store.knownProjects {
                items.append(.toggle(project.displayName, isOn: store.filter.projectKey == project.key) {
                    store.filter.projectKey = project.key
                })
            }
            return items
        }) {
            Image(systemName: "folder").font(Theme.Typography.ui(.label)).accessibilityHidden(true)
            Text(selected?.displayName ?? "Project").font(Theme.Typography.labelMono).lineLimit(1)
        }
    }

    private var assigneeFilter: some View {
        TaskMenuButton(items: {
            var items: [PopoverMenu.Item] = [
                .toggle("Anyone", isOn: store.filter.assignee == .anyone) { store.filter.assignee = .anyone },
            ]
            if store.canFilterByMe {
                items.append(.toggle("Assigned to Me", isOn: store.filter.assignee == .me) { store.filter.assignee = .me })
            }
            items.append(.toggle("Unassigned", isOn: store.filter.assignee == .unassigned) {
                store.filter.assignee = .unassigned
            })
            let people = store.knownAssignees.filter { !$0.isMe }
            if !people.isEmpty {
                items.append(.divider)
                for option in people {
                    items.append(.toggle(option.user.name, isOn: store.filter.assignee == .user(id: option.user.id)) {
                        store.filter.assignee = .user(id: option.user.id)
                    })
                }
            }
            return items
        }) {
            Image(systemName: "person").font(Theme.Typography.ui(.label)).accessibilityHidden(true)
            Text(assigneeTitle).font(Theme.Typography.labelMono).lineLimit(1)
        }
    }

    private var assigneeTitle: String {
        switch store.filter.assignee {
        case .anyone: "Assignee"
        case .me: "Me"
        case .unassigned: "Unassigned"
        case .user(let id): store.knownAssignees.first { $0.user.id == id }?.user.name ?? "Assignee"
        }
    }

    // MARK: - Tazelik

    /// "Updated 10s ago" — görünen kaynakların en eski tazelemesi.
    private var freshness: some View {
        TimelineView(.periodic(from: .now, by: Self.tickSeconds)) { context in
            HStack(spacing: Theme.Spacing.sm) {
                if store.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else if let oldest = store.visibleSources.compactMap(\.lastUpdated).min() {
                    Text("Updated \(TaskPresentation.relative(oldest, now: context.date))")
                        .font(Theme.Typography.mono(.caption))
                        .foregroundStyle(Theme.textMuted)
                }
                IconButton(systemName: "arrow.clockwise", label: "Refresh") {
                    Task { await store.refreshAll() }
                }
                .disabled(store.isRefreshing)
            }
        }
    }
}
