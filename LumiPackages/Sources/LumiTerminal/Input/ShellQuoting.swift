import Foundation

/// Drop edilen dosya path'lerinin shell-güvenli quote'lanması (karar 11 —
/// Electron'daki "boşluklu path bozulur" bug'ı taşınmaz).
enum ShellQuoting {
    private static let safeCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+=:,@%"
    )

    static func quote(_ path: String) -> String {
        guard !path.isEmpty else { return "''" }
        if path.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return path
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func joinedPaths(_ paths: [String]) -> String {
        paths.map(quote).joined(separator: " ")
    }
}
