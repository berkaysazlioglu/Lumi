import Foundation
import LumiKit
import Observation

/// Task'i gerçek bir ajana veren koşucu (karar 137, Faz 3).
///
/// Akış: (gerekirse) task'e özel workspace → task kapsamlı MCP oturumu
/// (`get_task`, `submit_for_review`) → çalışma alanını güvenilir işaretle →
/// **görünür, normal** bir claude terminali (`claude <prompt> --model …
/// --mcp-config … --allowedTools …`; `--session-id` enjeksiyonu korunur) →
/// terminalin durumunu izleyip `TaskAgentState`'e çevir. Ajan
/// `submit_for_review`'u çağırınca akışa `.submitted` düşer; store task'i
/// In Review'a taşır. Terminal kapanınca MCP oturumu düşer.
@MainActor
public final class LiveTaskAgentRunner: TaskAgentRunning {
    public typealias WorkspaceCreator = @MainActor (_ projectPath: String, _ branch: String) async throws -> String

    private let terminals: TerminalListStore
    private let tools: any TaskAgentToolServing
    private let createWorkspace: WorkspaceCreator
    private let trust: @MainActor (String) -> Void
    private let reattachWait: Duration

    public init(
        terminals: TerminalListStore,
        tools: any TaskAgentToolServing,
        createWorkspace: @escaping WorkspaceCreator,
        trust: @escaping @MainActor (String) -> Void,
        reattachWait: Duration = .seconds(10)
    ) {
        self.terminals = terminals
        self.tools = tools
        self.createWorkspace = createWorkspace
        self.trust = trust
        self.reattachWait = reattachWait
    }

    public var isPreview: Bool { false }

    public func start(_ request: TaskAgentRequest) -> AsyncStream<TaskAgentEvent> {
        AsyncStream { continuation in
            // Güçlü yakalama bilinçli: akış sürdükçe koşucu yaşar (döngü yok —
            // koşucu akışı tutmaz).
            let task = Task { @MainActor in
                await self.run(request, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func reattach(sessionID: String, task key: TaskKey) -> AsyncStream<TaskAgentEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                guard let meta = await self.awaitTerminal(sessionID: sessionID) else {
                    continuation.finish()
                    return
                }
                self.terminals.setCardBadge(key.id, for: meta.id)
                continuation.yield(.started(meta.id, sessionID: sessionID))
                await self.observe(meta.id, submission: SubmissionFlag(), continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Açılışta resume edilen terminaller listeye olaylarla biraz geç girer;
    /// oturumu taşıyan terminal `reattachWait` boyunca beklenir.
    private static let reattachPoll: Duration = .milliseconds(250)

    private func awaitTerminal(sessionID: String) async -> TerminalMeta? {
        let attempts = max(1, Int(reattachWait / Self.reattachPoll))
        for _ in 0..<attempts {
            if let meta = terminals.terminals.first(where: { $0.claudeSessionID == sessionID }) { return meta }
            try? await Task.sleep(for: Self.reattachPoll)
            if Task.isCancelled { return nil }
        }
        return nil
    }

    // MARK: - Başlatma

    private func run(_ request: TaskAgentRequest, continuation: AsyncStream<TaskAgentEvent>.Continuation) async {
        let checkout: String
        switch request.checkout {
        case .existing(let path):
            checkout = path
        case .newWorkspace(let projectPath, let branch):
            do {
                checkout = try await createWorkspace(projectPath, branch)
                continuation.yield(.checkout(checkout))
            } catch {
                continuation.yield(.failed("Couldn't create the workspace: \(Self.message(error))"))
                return
            }
        }
        guard !Task.isCancelled else { return }

        let submission = SubmissionFlag()
        let session: TaskAgentToolSession
        do {
            session = try await tools.register(details: request.details) { summary in
                await MainActor.run {
                    submission.isSubmitted = true
                    continuation.yield(.state(.submitted(summary: summary)))
                }
                return "Done — the task is now In Review and your summary is shown to the user. You can stop here."
            }
        } catch {
            continuation.yield(.failed("Couldn't start Lumi's task tools: \(Self.message(error))"))
            return
        }
        defer { Task { [tools] in await tools.unregister(session) } }

        // İlk prompt ilk-açılış güven menüsünde takılmasın (karar 89).
        trust(checkout)
        guard let meta = terminals.spawn(
            in: checkout,
            command: Self.command(for: request, mcpConfig: session.configPath),
            task: "\(request.task.id) · \(request.taskTitle)"
        ) else {
            continuation.yield(.failed("Lumi could not open a terminal in \(checkout)."))
            return
        }
        terminals.setCardBadge(request.task.id, for: meta.id)
        continuation.yield(.started(meta.id, sessionID: meta.claudeSessionID))
        await observe(meta.id, submission: submission, continuation: continuation)
    }

    /// Prompt konumsal argüman olarak ÖNCE gelir: `--mcp-config` ve
    /// `--allowedTools` çok değerli seçeneklerdir, arkalarındaki argümanı yutarlar.
    static func command(for request: TaskAgentRequest, mcpConfig: String) -> String {
        var parts = [AgentProvider.claude.launchCommand, shellQuoted(request.prompt)]
        if let model = request.agent.model { parts += ["--model", model.rawValue] }
        parts += ["--mcp-config", shellQuoted(mcpConfig), "--allowedTools", TaskAgentTools.allowedTools]
        if let directory = request.attachmentDirectory { parts += ["--add-dir", shellQuoted(directory)] }
        return parts.joined(separator: " ")
    }

    // MARK: - İzleme

    /// Terminal durumunu, değiştikçe ve terminal kapanana kadar yayınlar.
    private func observe(
        _ id: TerminalID, submission: SubmissionFlag, continuation: AsyncStream<TaskAgentEvent>.Continuation
    ) async {
        var last: TaskAgentState?
        var hasStarted = false
        // `spawn` meta'yı hemen döner ama terminal listeye `.spawned` olayıyla
        // biraz sonra girer: listede hiç görünmemiş terminal "kapandı" değildir.
        var hasAppeared = false
        while !Task.isCancelled {
            let meta = terminals.terminals.first { $0.id == id }
            if meta != nil { hasAppeared = true }
            if let meta, meta.status == .working { hasStarted = true }
            let state = hasAppeared
                ? Self.state(meta: meta, isAwaitingDecision: terminals.awaitingDecisionIDs.contains(id), hasStarted: hasStarted)
                : .starting
            // Teslimden sonra çalışma/bekleme durumları çipi ezmez; yalnız kapanış.
            if !submission.isSubmitted || state == .exited, state != last {
                continuation.yield(.state(state))
                last = state
            }
            if state == .exited { return }
            await nextChange()
        }
    }

    static func state(meta: TerminalMeta?, isAwaitingDecision: Bool, hasStarted: Bool) -> TaskAgentState {
        guard let meta else { return .exited }
        if isAwaitingDecision { return .needsInput }
        switch meta.status {
        case .working: return .working
        case .waitingUnseen, .waitingFocused, .waitingSeen, .error: return .idle
        case .idle:
            // Claude çıktı, düz shell kaldı: ajan bitti sayılır.
            return hasStarted && meta.provider == nil ? .exited : (hasStarted ? .idle : .starting)
        }
    }

    /// Terminal listesinde ya da karar bekleme kümesinde bir sonraki değişim.
    private func nextChange() async {
        let gate = OnceGate()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
                gate.arm(resume)
                withObservationTracking {
                    _ = terminals.terminals
                    _ = terminals.awaitingDecisionIDs
                } onChange: {
                    gate.fire()
                }
            }
        } onCancel: {
            gate.fire()
        }
    }

    private static func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// Teslimin bayrağı — MCP kapanışı ile izleme döngüsü arasında paylaşılır.
private final class SubmissionFlag: @unchecked Sendable {
    var isSubmitted = false
}

/// Devamı yalnız bir kez sürdüren kapı (gözlem + iptal yarışı).
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if fired {
            lock.unlock()
            continuation.resume()
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func fire() {
        lock.lock()
        fired = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
