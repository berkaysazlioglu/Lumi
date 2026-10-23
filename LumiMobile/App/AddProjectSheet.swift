import SwiftUI
import LumiMobileKit

/// `+` ▸ Add Project: the Mac's repos that aren't in Projects yet, grouped by
/// the folder they live in (roots, or a root's category folders), searchable.
/// Tapping a repo adds it to the Mac's Projects (decision 91's one phone write).
struct AddProjectSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private static let rowVerticalPadding: CGFloat = 4

    var body: some View {
        let addable = model.projectsSnapshot.addable
        let groups = addableGroups(addable, locations: model.projectsSnapshot.looseLocations, query: query)
        NavigationStack {
            List {
                if query.isEmpty { header(count: addable.count).listRowBackground(Color.clear) }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.repos) { repoRow($0) }
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LumiPalette.background)
            .overlay { emptyState(addableIsEmpty: addable.isEmpty, noMatches: groups.isEmpty) }
            .navigationTitle("Add Project")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search projects on your Mac")
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

    // MARK: - Pieces

    private func header(count: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(LumiPalette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Projects on your Mac")
                    .font(.headline).foregroundStyle(LumiPalette.textPrimary)
                Text(count == 1 ? "1 project isn't in Projects yet. Tap to add it — it shows up on the Mac too."
                                : "\(count) projects aren't in Projects yet. Tap one to add it — it shows up on the Mac too.")
                    .font(.footnote).foregroundStyle(LumiPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionHeader(_ group: AddableGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.title == "~" ? "house" : "folder")
            Text(group.title).lineLimit(1).truncationMode(.head)
            Spacer(minLength: 8)
            Text("\(group.repos.count)").monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(LumiPalette.textSecondary)
        .textCase(nil)
    }

    private func repoRow(_ repo: Repo) -> some View {
        Button {
            Task { await model.addProject(path: repo.path) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(LumiPalette.accent)
                Text(repo.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(LumiPalette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(LumiPalette.accent)
            }
            .padding(.vertical, Self.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(LumiPalette.elevated)
        .listRowSeparatorTint(LumiPalette.border)
        .accessibilityLabel("Add \(repo.name)")
        .accessibilityHint(repo.path)
    }

    @ViewBuilder
    private func emptyState(addableIsEmpty: Bool, noMatches: Bool) -> some View {
        if addableIsEmpty {
            ContentUnavailableView("No More Projects", systemImage: "checkmark.circle",
                                   description: Text("Every project on your Mac is already in Projects."))
        } else if noMatches {
            ContentUnavailableView.search(text: query)
        }
    }
}
