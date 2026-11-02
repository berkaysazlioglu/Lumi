import Foundation
import LumiKit

/// Bellekte yaşayan mod klasörü — gerçek `~/.lumi/mods`'a dokunmaz.
public actor FakeClaudeModService: ClaudeModServicing {
    public nonisolated let directory: String
    public private(set) var installCount = 0
    public var failure: Error?
    private var mods: [ClaudeMod]

    public init(directory: String = "/tmp/lumi-tests/.lumi/mods", mods: [ClaudeMod] = []) {
        self.directory = directory
        self.mods = mods
    }

    public func setFailure(_ value: Error?) { failure = value }
    public func setMods(_ value: [ClaudeMod]) { mods = value }

    public func installBundled() async throws {
        if let failure { throw failure }
        installCount += 1
    }

    public func list() async -> [ClaudeMod] { mods }
}
