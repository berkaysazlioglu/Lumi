import Foundation
import LumiKit

/// `QuickCommandBackgroundLaunching` test ikamesi: başlatmaları kaydeder.
public actor FakeQuickCommandBackgroundLauncher: QuickCommandBackgroundLaunching {
    public private(set) var launches: [(script: String, directory: String, log: String)] = []
    public var errorToThrow: LumiError?

    public init() {}

    public func setError(_ error: LumiError?) { errorToThrow = error }

    public func launch(scriptPath: String, workingDirectory: String, logPath: String) throws {
        if let errorToThrow { throw errorToThrow }
        launches.append((scriptPath, workingDirectory, logPath))
    }
}
