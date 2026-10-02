import Foundation

/// Settings ▸ About'ta gösterilen uygulama bilgisi.
///
/// `Info.plist`'ten okunur: sürüm `CFBundleShortVersionString`, commit
/// `Scripts/make-app.sh`'ın yazdığı `LumiGitCommit`. `swift run` ile koşan
/// geliştirme build'inde plist yoktur — sürüm `dev` olur, commit gizlenir.
public struct AppAboutInfo: Equatable {
    static let repositoryURL = URL(string: "https://github.com/berkaysazlioglu/Lumi")!
    static let releasesURL = URL(string: "https://github.com/berkaysazlioglu/Lumi/releases")!

    static let devVersion = "dev"

    public let version: String
    let commit: String?
    let system: String

    /// Sürüm satırı: `0.8.0 (0b373a1)` ya da yalnız `0.8.0`.
    var versionLine: String {
        guard let commit else { return version }
        return "\(version) (\(commit))"
    }

    init(info: [String: Any]?, system: String) {
        let version = (info?["CFBundleShortVersionString"] as? String).flatMap(Self.nonEmpty)
        self.version = version ?? Self.devVersion
        let commit = (info?["LumiGitCommit"] as? String).flatMap(Self.nonEmpty)
        self.commit = commit == "unknown" ? nil : commit
        self.system = system
    }

    public static var current: AppAboutInfo {
        AppAboutInfo(info: Bundle.main.infoDictionary, system: systemLine)
    }

    private static var systemLine: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(architecture)"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #else
        return "Intel (x86_64)"
        #endif
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
