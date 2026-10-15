import Foundation

/// İndirilmiş, doğrulanmış ve kurulmayı bekleyen sürüm (karar 118).
public struct StagedAppUpdate: Sendable, Equatable {
    public let release: AppRelease
    /// Sahnelenmiş `Lumi.app` — kurulumda olduğu gibi yerine kopyalanır.
    public let appPath: String

    public init(release: AppRelease, appPath: String) {
        self.release = release
        self.appPath = appPath
    }
}

/// Çalışan kopya kendini güncelleyebilir mi (karar 118).
public enum AppUpdateInstallSupport: Sendable, Equatable {
    case supported
    /// Developer ID ile imzalı değil (`swift run`, ad-hoc ya da Apple
    /// Development imzalı yerel build) — yerel build'i release'le ezmemek
    /// için sessizce kapalıdır.
    case unsignedBuild
    /// Bundle ya da bulunduğu klasör yazılamıyor (translocation, salt-okunur
    /// disk, yönetici olmayan kullanıcı). Kullanıcı taşıyabilir ya da elle
    /// indirebilir.
    case readOnlyLocation(path: String)

    public var isSupported: Bool { self == .supported }
}

/// Kurulumun ne zaman yapılacağı — dialogdaki iki seçim (karar 118).
public enum AppUpdateInstallTiming: Sendable, Equatable {
    /// Lumi kapanınca kurulur, yeniden açılmaz.
    case onQuit
    /// Şimdi kapanır, kurulur ve yeniden açılır.
    case restartNow
}
