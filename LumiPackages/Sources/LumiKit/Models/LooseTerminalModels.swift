import Foundation

/// Karar 108: projesiz ("serbest") terminallerin saf kuralları.
///
/// Serbest terminal ayrı bir bayrak taşımaz — `TerminalMeta.repoPath` yalnız
/// cwd'dir; yol hiçbir projeye, yönetilen workspace'e ya da açık checkout'a ait
/// değilse terminal serbesttir. Kural her okumada yeniden uygulanır: serbest
/// yol sonradan proje olarak eklenirse terminal o projenin altına geçer.
public enum LooseTerminalRule {
    public static func isLoose(
        path: String,
        projectPaths: some Sequence<String>,
        workspacePaths: some Sequence<String>,
        openTabs: some Sequence<String>
    ) -> Bool {
        let target = LooseTerminalPath.normalized(path)
        let owned = Array(projectPaths) + Array(workspacePaths) + Array(openTabs)
        return !owned.contains { LooseTerminalPath.normalized($0) == target }
    }
}

/// Serbest terminal yollarının normalleştirmesi ve kullanıcıya dönük etiketi.
public enum LooseTerminalPath {
    /// Baştaki `~` home'a açılır (`~user` desteklenmez — `RepoService.expand`
    /// paritesi), `.`/`..` ve sondaki `/` temizlenir. Symlink çözülmez:
    /// `/private/tmp` gibi yollar kullanıcının verdiği hâliyle kalır (karar 70).
    public static func normalized(_ path: String, home: String = NSHomeDirectory()) -> String {
        let expanded: String
        if path == "~" {
            expanded = home
        } else if path.hasPrefix("~/") {
            expanded = home + String(path.dropFirst(1))
        } else {
            expanded = path
        }
        // `standardizedFileURL`/`standardizingPath` `/private` önekini atar;
        // `standardized` yalnız sözdizimseldir, çift `/`'ı da bileşenler toplar.
        let components = URL(fileURLWithPath: expanded).standardized.path.split(separator: "/")
        return "/" + components.joined(separator: "/")
    }

    /// Home altındaki yol `~` ile kısaltılır (`~`, `~/Desktop`); dışındaki yol
    /// olduğu gibi kalır.
    public static func displayLabel(_ path: String, home: String = NSHomeDirectory()) -> String {
        let normalizedPath = normalized(path, home: home)
        let normalizedHome = normalized(home, home: home)
        if normalizedPath == normalizedHome { return "~" }
        guard normalizedPath.hasPrefix(normalizedHome + "/") else { return normalizedPath }
        return "~" + String(normalizedPath.dropFirst(normalizedHome.count))
    }
}

/// `New ⌄` menüsünün konum bölümündeki tek aday.
public struct LooseTerminalLocation: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Kullanıcının ev dizini — her zaman ilk aday ve varsayılan.
        case home
        /// Settings'teki projeler kökü ya da `additionalPaths` `root` girdisi.
        case sourceRoot
        /// Daha önce serbest terminal açılan konum (`recentLooseLocations`).
        case recent
    }

    public var id: String { path }
    public let path: String
    public let kind: Kind
    public let label: String

    public init(path: String, kind: Kind, label: String) {
        self.path = path
        self.kind = kind
        self.label = label
    }
}

/// Konum adaylarının ve "son kullanılanlar" listesinin saf üretimi.
public enum LooseTerminalLocations {
    /// `ui-state.json` → `recentLooseLocations` üst sınırı.
    public static let recentLimit = 5

    /// Sıra: home → kökler (projeler kökü, sonra `additionalPaths` `root`
    /// girdileri) → son kullanılanlar. Yollar normalleştirilerek tekilleştirilir;
    /// boş kök atlanır, son kullanılan bir kökü/home'u tekrar etmez.
    public static func candidates(
        projectsRoot: String,
        additionalPaths: [AdditionalPath],
        recent: [String],
        home: String = NSHomeDirectory()
    ) -> [LooseTerminalLocation] {
        let roots = [projectsRoot] + additionalPaths.filter { $0.type == .root }.map(\.path)
        let ordered: [(String, LooseTerminalLocation.Kind)] =
            [(home, .home)]
            + roots.map { ($0, .sourceRoot) }
            + recent.prefix(recentLimit).map { ($0, .recent) }

        var seen = Set<String>()
        return ordered.compactMap { raw, kind in
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let path = LooseTerminalPath.normalized(raw, home: home)
            guard seen.insert(path).inserted else { return nil }
            return LooseTerminalLocation(
                path: path,
                kind: kind,
                label: LooseTerminalPath.displayLabel(path, home: home)
            )
        }
    }

    /// Yeni açılan konumu en başa alır; aynı yolun eski kaydı düşer ve liste
    /// `recentLimit`'te kesilir.
    public static func recording(
        _ path: String,
        into recent: [String],
        home: String = NSHomeDirectory()
    ) -> [String] {
        var seen = Set<String>()
        let unique = ([path] + recent)
            .map { LooseTerminalPath.normalized($0, home: home) }
            .filter { seen.insert($0).inserted }
        return Array(unique.prefix(recentLimit))
    }
}

/// Projects ▸ `Other` grubunun tek dizini: o dizinde açık serbest terminaller.
public struct LooseTerminalGroup: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let label: String
    public let terminals: [TerminalMeta]

    public init(path: String, label: String, terminals: [TerminalMeta]) {
        self.path = path
        self.label = label
        self.terminals = terminals
    }
}
