import Foundation

/// Projenin kimlik rengi (karar 120). Model renk BİLMEZ — yalnız kimliktir;
/// tonlar LumiUI `Theme.ProjectTint`'te tek yerde durur. `rawValue`,
/// `config.json`'daki `projectColors` sözlüğüne yazılan değerdir (karar 9) —
/// case adı değiştirilirse diskteki seçimler okunmaz.
///
/// Palet bilinçli olarak dardır (kullanıcı isteği: "4-5 renk, özgür olmasınlar";
/// ekiyle 7 renk): mor (aktif kart ring'i), sarı (dikkat, karar 77 — limon ve kum
/// sarısı denendi, dikkat amber'ine fazla yakın okundu) ve kırmızı (hata) zaten
/// başka bir şey söylediği için listede yoktur.
public enum ProjectColor: String, Sendable, Equatable, Hashable, CaseIterable {
    case blue
    case teal
    case pink
    case orange
    case lime
    case green
    case fuchsia

    /// Menüde görünen ad.
    public var title: String { rawValue.capitalized }
}

/// Terminal → sahip proje → renk (karar 120). Sahiplik burada YENİDEN
/// çözülmez: çağıran mevcut çözümü verir (`NavigationStore.projectPath(containing:)`
/// — proje kökü + yönetilen workspace'ler + worktree'ler). Sahibi olmayan yol
/// serbest terminaldir (karar 108) ve renksizdir.
public enum ProjectColorResolver {
    public static func color(
        forCheckout checkout: String,
        colors: [String: ProjectColor],
        owningProject: (String) -> String?
    ) -> ProjectColor? {
        guard !colors.isEmpty, let project = owningProject(checkout) else { return nil }
        return colors[project]
    }

    /// Yüzeydeki her terminalin rengi; renksiz terminal sözlükte yer almaz.
    /// Hiç renk atanmamışsa sahiplik hiç sorulmaz (bugünkü görünümün maliyeti sıfır).
    public static func colors(
        for terminals: [TerminalMeta],
        colors: [String: ProjectColor],
        owningProject: (String) -> String?
    ) -> [TerminalID: ProjectColor] {
        guard !colors.isEmpty else { return [:] }
        var byCheckout: [String: ProjectColor?] = [:]
        var result: [TerminalID: ProjectColor] = [:]
        for meta in terminals {
            let resolved: ProjectColor?
            if let cached = byCheckout[meta.repoPath] {
                resolved = cached
            } else {
                resolved = color(forCheckout: meta.repoPath, colors: colors, owningProject: owningProject)
                byCheckout[meta.repoPath] = .some(resolved)
            }
            if let resolved { result[meta.id] = resolved }
        }
        return result
    }
}

/// Terminal kartı kenarlığının öncelik kuralı (karar 120) — view'sız, tek yerde:
/// seçili (proje rengi tam opak + aynı renkte hale; renksiz projede accent) >
/// dikkat (karar 77, sarı) > dinlenme (proje rengi soluk) > border.
/// Proje rengi bir KİMLİKTİR: seçili kartta da kimlik korunur, dikkat sarısı
/// ise yalnız seçili olmayan kartta görünür (tanım gereği seçiliyle dışlaşır).
public enum TerminalBorderEmphasis: Equatable, Sendable {
    /// Seçili kart; `nil` = renksiz proje (accent ring + mor hale).
    case active(ProjectColor?)
    case attention
    case project(ProjectColor)
    case rest

    public static func resolve(
        isActive: Bool,
        needsAttention: Bool,
        projectColor: ProjectColor?
    ) -> TerminalBorderEmphasis {
        if isActive { return .active(projectColor) }
        if needsAttention { return .attention }
        if let projectColor { return .project(projectColor) }
        return .rest
    }
}
