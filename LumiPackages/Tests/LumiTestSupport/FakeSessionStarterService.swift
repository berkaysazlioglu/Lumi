import Foundation
import LumiKit

/// `SessionStarterServicing` fake'i — başlatılan prompt'ları kaydeder,
/// istenirse hata fırlatır (karar 5 hata yolu).
public actor FakeSessionStarterService: SessionStarterServicing {
    public private(set) var startedPrompts: [String] = []
    private var errorToThrow: LumiError?

    public init() {}

    public func setError(_ error: LumiError?) { errorToThrow = error }

    public func start(prompt: String) async throws {
        startedPrompts.append(prompt)
        if let errorToThrow { throw errorToThrow }
    }
}
