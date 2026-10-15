import Foundation
import LumiKit

/// `AppUpdateInstalling` test ikamesi (karar 118): ağ, disk ve launchd yok.
public actor FakeAppUpdateInstaller: AppUpdateInstalling {
    public nonisolated let support: AppUpdateInstallSupport
    private var prepareError: LumiError?
    private var scheduleError: LumiError?
    private var pendingFailure: String?
    public private(set) var preparedVersions: [String] = []
    public private(set) var scheduled: [(version: String, relaunch: Bool)] = []

    public init(
        support: AppUpdateInstallSupport = .supported,
        prepareError: LumiError? = nil,
        pendingFailure: String? = nil
    ) {
        self.support = support
        self.prepareError = prepareError
        self.pendingFailure = pendingFailure
    }

    public func setPrepareError(_ error: LumiError?) {
        prepareError = error
    }

    public func setScheduleError(_ error: LumiError?) {
        scheduleError = error
    }

    public nonisolated func installSupport() -> AppUpdateInstallSupport { support }

    public func prepare(_ release: AppRelease) async throws -> StagedAppUpdate {
        preparedVersions.append(release.version.description)
        if let prepareError { throw prepareError }
        return StagedAppUpdate(release: release, appPath: "/staged/\(release.version)/Lumi.app")
    }

    public func scheduleInstall(_ update: StagedAppUpdate, relaunch: Bool) async throws {
        if let scheduleError { throw scheduleError }
        scheduled.append((update.release.version.description, relaunch))
    }

    public func consumeInstallFailure() async -> String? {
        defer { pendingFailure = nil }
        return pendingFailure
    }
}
