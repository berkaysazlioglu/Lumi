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
    /// Karar 93: projenin tek `Start App` komutu mu, sıradan bir action mı.
    public let role: QuickCommandRole

    public init(
        id: String = UUID().uuidString, projectPath: String, name: String, script: String,
        request: String = "", role: QuickCommandRole = .action
    ) {
        self.id = id
        self.projectPath = projectPath
        self.name = name
        self.script = script
        self.request = request
        self.role = role
    }

    /// Projenin boş `Start App` taslağı (adı sabittir).
    public static func startApp(projectPath: String) -> ProjectQuickCommand {
        ProjectQuickCommand(projectPath: projectPath, name: QuickCommandRole.startAppName, script: "", role: .startApp)
    }

    /// Kaydedilebilir mi: ad ve gövde boş olamaz.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Komutun rolü (karar 93).
public enum QuickCommandRole: String, Sendable, Equatable {
    /// Checkout menüsünün `Actions` alt menüsünde listelenir, terminalde koşar.
    case action
    /// Proje başına en fazla bir tane: gövdesi doluysa checkout menüsünün en
    /// başında durur ve terminal açmadan arka planda koşar.
    case startApp

    public static let startAppName = "Start App"

    public var runsInBackground: Bool { self == .startApp }
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

public enum QuickCommandNaming {
    public static let maxNameLength = 40

    /// Adı boş bırakılmış komuta Claude tarifinden ad önerisi: ilk dolu
    /// satır, sondaki noktalama atılır, uzunsa kelime sınırında kesilir.
    public static func suggestedName(from request: String) -> String {
        let line = request.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: ".!?:;,"))
        guard trimmed.count > maxNameLength else { return trimmed }
        let prefix = String(trimmed.prefix(maxNameLength))
        // Kesim noktası zaten kelime sınırıysa son kelime tamdır.
        let endsAtWord = trimmed.dropFirst(maxNameLength).first == " "
        let cut = endsAtWord ? prefix : (prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix)
        return cut + "…"
    }
}

/// Bir komutun bir checkout'ta çalıştırılışı (karar 92) — saf hesaplar.
///
/// Çok satırlı script PTY'ye satır satır yazılınca (`if`/döngü/heredoc)
/// kabuğun etkileşimli ayrıştırmasına takılır; bu yüzden çözülmüş gövde bir
/// dosyaya yazılır ve terminale yalnız `sh '<dosya>'` satırı girilir.
public enum QuickCommandRun {
    /// Komut + checkout başına sabit ad: aynı checkout'ta tekrar çalıştırma
    /// dosyayı ezer (birikmez), farklı checkout'larda art arda çalıştırma
    /// birbirinin dosyasını ezmez (terminal satırı gecikmeli okunur).
    public static func fileName(commandID: String, checkoutName: String) -> String {
        let slug = WorkspaceName.slug(checkoutName)
        return "\(WorkspaceName.slug(commandID))-\(slug.isEmpty ? "checkout" : slug).sh"
    }

    /// Başlık yorumu eklenir; script `#!` ile başlıyorsa o satır EN ÜSTTE
    /// kalır (başlık önüne girerse shebang anlamını yitirir).
    public static func scriptContents(_ command: ProjectQuickCommand, context: QuickCommandContext) -> String {
        var body = QuickCommandTemplate.resolve(command.script, context: context)
        if !body.hasSuffix("\n") { body += "\n" }
        let header = "# Lumi action: \(command.name.replacingOccurrences(of: "\n", with: " "))\n"
        guard body.hasPrefix("#!"), let newline = body.firstIndex(of: "\n") else { return header + body }
        let shebang = body[...newline]
        return shebang + header + body[body.index(after: newline)...]
    }

    /// Arka plan çalıştırmasının (karar 93) çıktı dosyası: script'in yanında `.log`.
    public static func logPath(scriptPath: String) -> String {
        (scriptPath as NSString).deletingPathExtension + ".log"
    }

    /// Terminale yazılan satır: yol tek tırnaklanır (içindeki `'` kaçırılır).
    public static func launchLine(scriptPath: String) -> String {
        "sh '\(scriptPath.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
