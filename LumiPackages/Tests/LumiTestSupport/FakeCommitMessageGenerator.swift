import Foundation
import LumiKit

/// `CommitMessageGenerating` test ikamesi: sabit yanıt ya da hata; istekler kaydedilir.
public actor FakeCommitMessageGenerator: CommitMessageGenerating {
    public var messageToReturn = "Update files"
    public var errorToThrow: LumiError?
    public var delay: Duration = .zero
    public private(set) var requests: [CommitMessageRequest] = []

    public init() {}

    public func setMessage(_ message: String) { messageToReturn = message }
    public func setError(_ error: LumiError?) { errorToThrow = error }
    public func setDelay(_ value: Duration) { delay = value }

    public func generate(_ request: CommitMessageRequest) async throws -> String {
        requests.append(request)
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let errorToThrow { throw errorToThrow }
        return messageToReturn
    }
}
