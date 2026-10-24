import Foundation
import LumiKit

/// Gerçek terminal açmayan önizleme koşucusu (Tasks planı, ajan önizlemesi).
///
/// Faz 3'te gerçek koşucu (terminal + Lumi MCP aracı) gelene kadar akışın
/// görünüşünü denemek içindir: başlar → çalışır → bir an izin bekler →
/// çalışır → işi teslim eder. UI bunu "Preview" rozetiyle söyler.
public struct PreviewTaskAgentRunner: TaskAgentRunning {
    /// Adımlar arası bekleme — testler sıfır verir.
    private let step: Duration

    public init(step: Duration = .seconds(3)) {
        self.step = step
    }

    public var isPreview: Bool { true }

    public func start(_ request: TaskAgentRequest) -> AsyncStream<TaskAgentEvent> {
        let step = step
        return AsyncStream { continuation in
            let task = Task {
                let script: [TaskAgentState] = [
                    .working,
                    .needsInput,
                    .working,
                    .submitted(summary: "Implemented \"\(request.taskTitle)\" and ran the tests. (preview — no real agent ran)"),
                ]
                continuation.yield(.started(nil))
                for state in script {
                    try? await Task.sleep(for: step)
                    if Task.isCancelled { break }
                    continuation.yield(.state(state))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
