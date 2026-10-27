import Foundation

/// Claude Code'un prompt'a yapıştırılan görseli kaydettiği dosya (karar 139).
/// Prompt'ta `[Image #N]` olarak görünür; dosya oturumun `images/` dizininde
/// `N.<uzantı>` adıyla durur.
public struct ClaudePastedImage: Sendable, Equatable, Identifiable {
    public let number: Int
    /// Mutlak yol.
    public let path: String

    public init(number: Int, path: String) {
        self.number = number
        self.path = path
    }

    public var id: Int { number }
    public var directory: String { (path as NSString).deletingLastPathComponent }
    public var fileName: String { (path as NSString).lastPathComponent }
    /// Chat'e yapıştırılan referans: Claude'un kendi yer tutucusuyla aynı id.
    public var reference: String { ClaudePastedImages.reference(number) }
}

/// Claude Code'un yapıştırılan görselleri sakladığı yerin saf bilgisi:
/// `/private/tmp/claude-<uid>/<cwd kodlaması>/<oturum kimliği>/images/N.png`.
/// Diske dokunmaz — listeleme ve varlık sorgusu çağıranın işidir.
public enum ClaudePastedImages {
    /// Claude'un `/tmp`'si; terminalde de `/private/tmp/...` olarak yazar.
    static let temporaryRoot = "/private/tmp"
    /// Claude yapıştırılan görseli bu uzantılardan biriyle kaydeder; sıra
    /// "önce bunu dene" sırasıdır (pano görseli PNG'dir).
    public static let fileExtensions = ["png", "jpg", "jpeg", "gif", "webp"]

    private static let placeholder = try? NSRegularExpression(pattern: #"\[Image #([1-9][0-9]{0,5})\]"#)

    /// Terminalin claude oturumunun görsel dizini. Cwd, `~/.claude/projects`
    /// kodlamasıyla (harf/rakam dışı her karakter `-`) yazılır.
    public static func directory(cwd: String, sessionID: String, userID: UInt32 = getuid()) -> String {
        let encoded = cwd.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
        return "\(temporaryRoot)/claude-\(userID)/\(encoded)/\(sessionID)/images"
    }

    /// Lumi'nin izlediği claude oturumu yoksa (`claudeSessionID == nil`) görsel
    /// dizini de bilinmez.
    public static func directory(for meta: TerminalMeta, userID: UInt32 = getuid()) -> String? {
        meta.claudeSessionID.map { directory(cwd: meta.repoPath, sessionID: $0, userID: userID) }
    }

    public static func reference(_ number: Int) -> String { "[Image #\(number)]" }

    /// `[Image #N]` metnindeki numara; yer tutucu değilse `nil`.
    public static func number(inReference text: String) -> Int? {
        guard let placeholder else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = placeholder.firstMatch(in: text, options: [.anchored], range: range),
              match.range.length == range.length else { return nil }
        return Int((text as NSString).substring(with: match.range(at: 1)))
    }

    /// Satırdaki yer tutucuların UTF-16 aralıkları.
    static func placeholderRanges(in line: NSString) -> [NSRange] {
        guard let placeholder else { return [] }
        return placeholder.matches(in: line as String, range: NSRange(location: 0, length: line.length)).map(\.range)
    }

    /// Numaranın aday dosya yolları, denenme sırasıyla.
    public static func candidatePaths(number: Int, in directory: String) -> [String] {
        fileExtensions.map { "\(directory)/\(number).\($0)" }
    }

    /// Dizin listesinden görseller, numaraya göre artan. Aynı numaranın birden
    /// çok uzantısı varsa `fileExtensions` sırasındaki ilki kalır.
    public static func images(fileNames: [String], in directory: String) -> [ClaudePastedImage] {
        var best: [Int: (rank: Int, name: String)] = [:]
        for name in fileNames {
            let stem = (name as NSString).deletingPathExtension
            let fileExtension = (name as NSString).pathExtension.lowercased()
            guard let rank = fileExtensions.firstIndex(of: fileExtension),
                  let number = Int(stem), number > 0, String(number) == stem else { continue }
            if let current = best[number], current.rank <= rank { continue }
            best[number] = (rank, name)
        }
        return best.keys.sorted().compactMap { number in
            best[number].map { ClaudePastedImage(number: number, path: "\(directory)/\($0.name)") }
        }
    }
}
