import Foundation
import LumiKit

/// Action step çalıştırıcısı (spec/13 §3.6). Daima YENİ terminal açar;
/// limit aşımı spawn'dan görünür hata olarak fırlar (karar 5/11).
struct ActionEngine: Sendable {
    /// `wait_for` rolling buffer'ı (karar 11 düzeltmesi): pattern chunk
    /// sınırına denk gelse de son 4KB içinde eşleşir.
    static let waitBufferLimit = 4096

    let terminal: any TerminalServicing

    func execute(
        _ action: Action,
        repoPath: String,
        provider: AgentProvider,
        builder: AgentCommandBuilder,
        taskLabel: String? = nil
    ) async throws -> TerminalMeta {
        let meta = try await terminal.spawn(
            repoPath: repoPath,
            task: taskLabel ?? action.label,
            command: nil
        )
        for (index, step) in action.steps.enumerated() {
            switch step {
            case .write(let content):
                let transformed = try builder.build(
                    content: content,
                    provider: provider,
                    claude: action.claude,
                    codex: action.codex
                )
                try await terminal.write(id: meta.id, text: transformed)

            case .waitFor(let pattern, let timeoutMs):
                guard let stream = await terminal.outputStream(id: meta.id) else {
                    throw LumiError.terminalNotFound(meta.id)
                }
                try await Self.waitFor(
                    pattern: pattern,
                    timeoutMs: timeoutMs,
                    stream: stream,
                    actionID: action.id,
                    stepIndex: index
                )

            case .delay(let ms):
                try await Task.sleep(for: .milliseconds(ms))
            }
        }
        return meta
    }

    /// Saf ve test edilebilir: stream + pattern + timeout → eşleşme veya
    /// `actionStepTimedOut` (spec/13 §3.1: timeout default 10000ms).
    static func waitFor(
        pattern: String,
        timeoutMs: Int,
        stream: AsyncStream<String>,
        actionID: String,
        stepIndex: Int
    ) async throws {
        guard (try? NSRegularExpression(pattern: pattern)) != nil else {
            throw LumiError.underlying(
                domain: "action",
                message: "invalid wait_for pattern: \(pattern)"
            )
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
                var buffer = ""
                for await chunk in stream {
                    buffer += chunk
                    if buffer.count > waitBufferLimit {
                        buffer = String(buffer.suffix(waitBufferLimit))
                    }
                    let range = NSRange(buffer.startIndex..., in: buffer)
                    if regex.firstMatch(in: buffer, options: [], range: range) != nil {
                        return
                    }
                }
                // Stream kapandı (terminal öldü) — eşleşme artık imkânsız
                throw LumiError.actionStepTimedOut(actionID: actionID, step: stepIndex)
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(timeoutMs))
                throw LumiError.actionStepTimedOut(actionID: actionID, step: stepIndex)
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }
}
