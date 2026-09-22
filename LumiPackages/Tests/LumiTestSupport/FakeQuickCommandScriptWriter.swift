import Foundation
import LumiKit

/// `QuickCommandScriptWriting` test ikamesi: yazımları kaydeder, diske dokunmaz.
public actor FakeQuickCommandScriptWriter: QuickCommandScriptWriting {
    public private(set) var writes: [(name: String, contents: String)] = []
    public var errorToThrow: LumiError?
    public let directory: String

    public init(directory: String = "/lumi/quick-commands") { self.directory = directory }

    public func setError(_ error: LumiError?) { errorToThrow = error }

    public func writeScript(named fileName: String, contents: String) throws -> String {
        if let errorToThrow { throw errorToThrow }
        writes.append((fileName, contents))
        return "\(directory)/\(fileName)"
    }
}
