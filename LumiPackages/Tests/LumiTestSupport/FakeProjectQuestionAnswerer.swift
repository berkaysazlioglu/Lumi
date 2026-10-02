import Foundation
import LumiKit

/// Test için sahte `ask_project` (karar 103 Faz 5): sabit cevap ya da hata,
/// çağrılar kaydedilir.
public final class FakeProjectQuestionAnswerer: ProjectQuestionAnswering, @unchecked Sendable {
    private let lock = NSLock()
    private var _questions: [(projectPath: String, question: String)] = []
    private var outcome: Result<ProjectAnswer, LumiError> = .success(ProjectAnswer(text: "cevap"))

    public init() {}

    public var questions: [(projectPath: String, question: String)] { lock.withLock { _questions } }

    public func stub(_ outcome: Result<ProjectAnswer, LumiError>) { lock.withLock { self.outcome = outcome } }

    public func ask(projectPath: String, question: String) async throws -> ProjectAnswer {
        let outcome = lock.withLock { () -> Result<ProjectAnswer, LumiError> in
            _questions.append((projectPath, question))
            return self.outcome
        }
        return try outcome.get()
    }
}
