import Foundation

/// A section of the Add Project sheet: the Mac folder that holds the repos.
public struct AddableGroup: Sendable, Equatable, Identifiable {
    /// Parent folder (absolute path).
    public let path: String
    /// `~`-abbreviated folder (`~/wkspaces/Swift`).
    public let title: String
    public let repos: [Repo]
    public var id: String { path }
}

/// Groups the Mac's addable repos by the folder they sit in — one section per
/// root when repos live directly under the roots, one per sub-folder (`Swift`,
/// `Unity`, …) when a root is organized into categories. `query` filters by
/// name or path (case/diacritic-insensitive). Sections and repos are sorted
/// by name; the home folder is read from the Mac's `~` location.
public func addableGroups(_ repos: [Repo], locations: [LooseLocation], query: String = "") -> [AddableGroup] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    let matching = needle.isEmpty ? repos : repos.filter {
        $0.name.localizedStandardContains(needle) || $0.path.localizedStandardContains(needle)
    }
    let home = locations.first { $0.label == "~" }?.path
    let byFolder = Dictionary(grouping: matching) { parentFolder(of: $0.path) }
    return byFolder
        .map { folder, repos in
            AddableGroup(
                path: folder,
                title: abbreviate(folder, home: home),
                repos: repos.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
}

private func parentFolder(of path: String) -> String {
    let parent = (path as NSString).deletingLastPathComponent
    return parent.isEmpty ? "/" : parent
}

private func abbreviate(_ path: String, home: String?) -> String {
    guard let home, !home.isEmpty else { return path }
    if path == home { return "~" }
    let prefix = home.hasSuffix("/") ? home : home + "/"
    return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
}
