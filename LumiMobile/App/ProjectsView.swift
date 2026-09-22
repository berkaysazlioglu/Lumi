import SwiftUI
import LumiMobileKit

struct ProjectsView: View {
    let model: AppModel
    @State private var collapsedProjects: Set<String> = []
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if !model.macOnline { offlineBanner }
                if model.projectTree.isEmpty {
                    emptyState
                } else {
                    ForEach(model.projectTree) { project in
                        projectSection(project)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Projects")
            // Mirror SessionListView's routing exactly: all sessions go to
            // TerminalSessionView, which internally branches to MobileChatView
            // when isChatSession returns true (Phase 2.1 routing already inside it).
            .navigationDestination(for: String.self) { sessionId in
                TerminalSessionView(model: model, sessionId: sessionId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { connectionDot }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(!model.macOnline || model.projectsSnapshot.addable.isEmpty)
                }
            }
            .sheet(isPresented: $showAdd) { AddProjectSheet(model: model) }
        }
    }

    @ViewBuilder
    private func projectSection(_ project: ProjectRowData) -> some View {
        let collapsed = collapsedProjects.contains(project.id)
        Section {
            if !collapsed {
                ForEach(project.checkouts) { checkout in
                    CheckoutRowView(checkout: checkout)
                }
            }
        } header: {
            Button {
                if !collapsedProjects.insert(project.id).inserted {
                    collapsedProjects.remove(project.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.purple)
                    Text(project.node.name).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus").font(.title).foregroundStyle(.secondary)
            Text("No projects yet").foregroundStyle(.secondary)
            Text("Add a project on the Mac, or use +").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }

    private var offlineBanner: some View {
        Label("Mac offline", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            .font(.callout).foregroundStyle(.orange)
    }

    private var connectionDot: some View {
        Circle()
            .fill(model.connection == .connected ? .green :
                  model.connection == .connecting ? .yellow : .red)
            .frame(width: 10, height: 10)
            .accessibilityLabel("Relay connection")
    }
}

private struct CheckoutRowView: View {
    let checkout: CheckoutRowData
    @State private var agentsCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // "workspace" kind → branch icon; "original" (main checkout) → house icon
                Image(systemName: checkout.node.kind == "workspace" ? "arrow.triangle.branch" : "house")
                    .font(.caption).foregroundStyle(.secondary)
                Text(checkout.node.title).font(.subheadline)
                if let branch = checkout.node.branch, !branch.isEmpty {
                    Text(branch)
                        .font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                // Show leading agent badge summary when agents row is collapsed
                if agentsCollapsed, let lead = checkout.agents.first {
                    HStack(spacing: 4) {
                        Circle().fill(Color(badge: lead.badge)).frame(width: 8, height: 8)
                        Text("\(checkout.agents.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            // Collapse/expand toggle only when there are multiple agents
            if checkout.agents.count > 1 {
                Button { agentsCollapsed.toggle() } label: {
                    HStack {
                        Text("\(checkout.agents.count) agents").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: agentsCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain).padding(.leading, 24)
            }
            if !agentsCollapsed || checkout.agents.count == 1 {
                ForEach(checkout.agents) { agent in AgentRowView(agent: agent) }
            }
        }
    }
}

private struct AgentRowView: View {
    let agent: AgentRowData

    var body: some View {
        NavigationLink(value: agent.id) {
            HStack(spacing: 8) {
                Circle().fill(Color(badge: agent.badge)).frame(width: 8, height: 8)
                Image(systemName: providerSymbol).font(.caption2).foregroundStyle(.secondary)
                Text(agent.title)
                    .font(.subheadline)
                    .foregroundStyle(agent.needsAttention ? Color.orange : .secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                Text(PhoneRelativeTime.shortLabel(
                    agent.lastActivityAt,
                    now: Date().timeIntervalSince1970 * 1000
                ))
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.leading, 24)
            .overlay(alignment: .leading) {
                if agent.needsAttention {
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange).frame(width: 3)
                }
            }
        }
    }

    private var providerSymbol: String {
        switch agent.provider {
        case "claude": "sparkle"
        case "codex": "chevron.left.forwardslash.chevron.right"
        default: "circle.fill"
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

private extension Color {
    init(badge: Badge) {
        switch badge {
        case .idle: self = .gray
        case .working: self = .blue
        case .waiting: self = .orange
        case .error: self = .red
        }
    }
}
