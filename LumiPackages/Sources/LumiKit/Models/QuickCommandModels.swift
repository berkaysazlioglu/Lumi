import Foundation

/// Projeye bağlı, checkout'tan bağımsız bir komut (karar 92).
///
/// Komut PROJE başına tanımlanır ve o projenin her checkout'unda (`main` ve
/// yönetilen workspace'ler) çalışır; yol yerine `{path}` gibi anahtarlar
/// taşıdığı için checkout'a göre çalışma anında çözülür
/// (`QuickCommandTemplate`). Persistence: `config.json` → `projectQuickCommands`.
public struct ProjectQuickCommand: Sendable, Equatable, Identifiable {
    public let id: String
    public let projectPath: String
    public var name: String
    /// `sh` gövdesi; anahtarlar çözülmeden saklanır.
    public var script: String
    /// Claude'a verilen son tarif — yeniden üretimde alan dolu gelsin diye
    /// saklanır. Elle yazılmış komutta boştur.
    public var request: String

    public init(id: String = UUID().uuidString, projectPath: String, name: String, script: String, request: String = "") {
        self.id = id
        self.projectPath = projectPath
        self.name = name
        self.script = script
        self.request = request
    }

    /// Kaydedilebilir mi: ad ve gövde boş olamaz.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Komut gövdesinde kullanılabilen anahtarlar (karar 92).
public enum QuickCommandPlaceholder: String, CaseIterable, Sendable {
    /// Komutun çalıştırıldığı checkout (`main` ya da workspace).
    case path
    /// Projenin kendi kökü — workspace'te çalışırken de ana checkout.
    case projectPath = "project_path"
    /// Checkout'un adı (`main` için proje adı).
    case name
    /// Checkout'un dalı; bilinmiyorsa boş.
    case branch

    public var token: String { "{\(rawValue)}" }

    public var summary: String {
        switch self {
        case .path: "Checkout the command runs in (main or a workspace)"
        case .projectPath: "Root of the original project"
        case .name: "Checkout name"
        case .branch: "Checkout branch (empty when unknown)"
        }
    }
}

/// Anahtarların çalışma anındaki değerleri.
public struct QuickCommandContext: Sendable, Equatable {
    public let path: String
    public let projectPath: String
    public let name: String
    public let branch: String

    public init(path: String, projectPath: String, name: String, branch: String) {
        self.path = path
        self.projectPath = projectPath
        self.name = name
        self.branch = branch
    }

    public func value(for placeholder: QuickCommandPlaceholder) -> String {
        switch placeholder {
        case .path: path
        case .projectPath: projectPath
        case .name: name
        case .branch: branch
        }
    }
}

public enum QuickCommandTemplate {
    /// Bilinen `{anahtar}`ları değerleriyle değiştirir. Değer ham yazılır —
    /// tırnaklama script'in işidir (`cd "{path}"`). `$` ile başlayan
    /// `${path}` bir shell değişkenidir ve dokunulmaz; bilinmeyen anahtarlar da
    /// olduğu gibi kalır.
    public static func resolve(_ script: String, context: QuickCommandContext) -> String {
        guard let pattern else { return script }
        let nsScript = script as NSString
        var result = ""
        var cursor = 0
        for match in pattern.matches(in: script, range: NSRange(location: 0, length: nsScript.length)) {
            let key = nsScript.substring(with: match.range(at: 1))
            guard let placeholder = QuickCommandPlaceholder(rawValue: key) else { continue }
            result += nsScript.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += context.value(for: placeholder)
            cursor = match.range.location + match.range.length
        }
        result += nsScript.substring(from: cursor)
        return result
    }

    private static let pattern: NSRegularExpression? = {
        let keys = QuickCommandPlaceholder.allCases.map(\.rawValue).joined(separator: "|")
        return try? NSRegularExpression(pattern: "(?<!\\$)\\{(\(keys))\\}")
    }()
}
