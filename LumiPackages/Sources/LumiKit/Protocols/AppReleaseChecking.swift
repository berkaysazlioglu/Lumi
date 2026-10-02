import Foundation

/// Yayınlanmış en son Lumi sürümünü okuyan servis yüzü (karar 102).
public protocol AppReleaseChecking: Sendable {
    /// Ağ, HTTP ya da biçim hatasında `LumiError.updateCheckFailed` fırlatır.
    func latestRelease() async throws -> AppRelease
}
