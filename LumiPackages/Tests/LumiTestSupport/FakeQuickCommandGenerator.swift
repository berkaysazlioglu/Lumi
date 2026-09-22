import Foundation
import LumiKit

/// `QuickCommandGenerating` test ikamesi: sabit script ya da hata; istekler kaydedilir.
public actor FakeQuickCommandGenerator: QuickCommandGenerating {
    public var scriptToReturn = "cd \"{path}\"\nmake\n"
    public var errorToThrow: LumiError?
    public var delay: Duration = .zero
    public private(set) var requests: [QuickCommandGenerationRequest] = []

    public init() {}

    public func setScript(_ script: String) { scriptToReturn = script }
    public func setError(_ error: LumiError?) { errorToThrow = error }
    public func setDelay(_ value: Duration) { delay = value }

    public func generate(_ request: QuickCommandGenerationRequest) async throws -> String {
        requests.append(request)
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let errorToThrow { throw errorToThrow }
        return scriptToReturn
    }
}
