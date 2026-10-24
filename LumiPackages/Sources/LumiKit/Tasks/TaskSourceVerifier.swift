import Foundation

/// Bağlanmadan önce koşan uygunluk testi (plan: "Verify").
///
/// Adapter'dan bağımsızdır — yalnız `TaskProviding` üstünden konuşur; bu yüzden
/// demo kaynakta da, ileride GitHub adapter'ında da aynı kontrol listesi
/// koşar. Her ajan protokolü biraz farklı yazacağı için sonuç, kullanıcının
/// ajana yapıştırabileceği bir rapora da çevrilir (`agentReport`).
public struct TaskVerificationStep: Sendable, Hashable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable, Hashable {
        case discovery
        case version
        case listTasks
        case listUsers
        case listProjects
        case create
        case updateStatus
        case delete
    }

    public enum Outcome: Sendable, Hashable {
        case pending
        case running
        case passed(String?)
        case warning(String)
        case skipped(String)
        case failed(String)

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    public let kind: Kind
    public var outcome: Outcome

    public init(kind: Kind, outcome: Outcome) {
        self.kind = kind
        self.outcome = outcome
    }

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .discovery: "Connect and authenticate"
        case .version: "Protocol version"
        case .listTasks: "List tasks"
        case .listUsers: "List users"
        case .listProjects: "List projects"
        case .create: "Create a test task"
        case .updateStatus: "Change a task's status"
        case .delete: "Delete the test task"
        }
    }
}

public struct TaskVerificationReport: Sendable, Hashable {
    public var steps: [TaskVerificationStep]
    /// Discovery başarılıysa kaynağın beyanı — bağlanırken saklanır.
    public var info: TaskSourceInfo?
    public var isFinished: Bool

    public init(steps: [TaskVerificationStep] = TaskVerificationStep.Kind.allCases.map {
        TaskVerificationStep(kind: $0, outcome: .pending)
    }, info: TaskSourceInfo? = nil, isFinished: Bool = false) {
        self.steps = steps
        self.info = info
        self.isFinished = isFinished
    }

    public var hasFailure: Bool { steps.contains { $0.outcome.isFailure } }
    public var canConnect: Bool { isFinished && !hasFailure && info != nil }

    mutating func set(_ kind: TaskVerificationStep.Kind, _ outcome: TaskVerificationStep.Outcome) {
        guard let index = steps.firstIndex(where: { $0.kind == kind }) else { return }
        steps[index].outcome = outcome
    }

    /// Ajan için düz metin rapor: yalnız başarısız/uyarılı adımlar ve neyin
    /// beklendiği. Token ya da adres içermez.
    public var agentReport: String {
        var lines = ["Lumi Tasks Protocol verification failed. Please fix the server so these checks pass:", ""]
        for step in steps {
            switch step.outcome {
            case .failed(let message): lines.append("- FAILED · \(step.title): \(message)")
            case .warning(let message): lines.append("- WARNING · \(step.title): \(message)")
            default: continue
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum TaskSourceVerifier {
    /// Test task'inin başlığı — kullanıcının listesinde görülürse ne olduğu belli olsun.
    public static let testTaskTitle = "[Lumi verify] temporary task — safe to delete"

    /// Her adım bittikçe `onUpdate` güncel raporla çağrılır.
    public static func run(
        _ provider: any TaskProviding,
        onUpdate: @MainActor (TaskVerificationReport) -> Void
    ) async -> TaskVerificationReport {
        var report = TaskVerificationReport()
        func step(_ kind: TaskVerificationStep.Kind, _ outcome: TaskVerificationStep.Outcome) async {
            report.set(kind, outcome)
            await onUpdate(report)
        }
        func skipRest(from kind: TaskVerificationStep.Kind, reason: String) async {
            let kinds = TaskVerificationStep.Kind.allCases
            guard let start = kinds.firstIndex(of: kind) else { return }
            for remaining in kinds[start...] { report.set(remaining, .skipped(reason)) }
            await onUpdate(report)
        }

        await step(.discovery, .running)
        let info: TaskSourceInfo
        do {
            info = try await provider.discover()
            report.info = info
            await step(.discovery, .passed(info.name))
        } catch {
            await step(.discovery, .failed(message(error)))
            await skipRest(from: .version, reason: "Needs a successful connection")
            report.isFinished = true
            await onUpdate(report)
            return report
        }

        guard info.isVersionSupported else {
            await step(.version, .failed(TaskProviderError.unsupportedVersion(info.version).errorDescription ?? ""))
            await skipRest(from: .listTasks, reason: "Unsupported protocol version")
            report.isFinished = true
            await onUpdate(report)
            return report
        }
        await step(.version, .passed("v\(info.version)"))

        await step(.listTasks, .running)
        do {
            let tasks = try await provider.listTasks()
            let flagged = tasks.filter(\.needsAttention).count
            if flagged > 0 {
                await step(.listTasks, .warning("\(flagged) task(s) have an invalid status or missing required field"))
            } else {
                await step(.listTasks, .passed("\(tasks.count) task(s)"))
            }
        } catch {
            await step(.listTasks, .failed(message(error)))
        }

        await optionalList(.listUsers, capability: .users, info: info, report: &report, onUpdate: onUpdate) {
            "\(try await provider.listUsers().count) user(s)"
        }
        await optionalList(.listProjects, capability: .projects, info: info, report: &report, onUpdate: onUpdate) {
            "\(try await provider.listProjects().count) project(s)"
        }

        await verifyWrites(provider, info: info, report: &report, onUpdate: onUpdate)
        report.isFinished = true
        await onUpdate(report)
        return report
    }

    private static func optionalList(
        _ kind: TaskVerificationStep.Kind,
        capability: TaskCapability,
        info: TaskSourceInfo,
        report: inout TaskVerificationReport,
        onUpdate: @MainActor (TaskVerificationReport) -> Void,
        call: () async throws -> String
    ) async {
        guard info.supports(capability) else {
            report.set(kind, .skipped("Not declared by the server"))
            await onUpdate(report)
            return
        }
        report.set(kind, .running)
        await onUpdate(report)
        do {
            report.set(kind, .passed(try await call()))
        } catch {
            report.set(kind, .failed(message(error)))
        }
        await onUpdate(report)
    }

    /// Yazma testleri yalnız kendi oluşturduğu task üzerinde koşar — kullanıcının
    /// gerçek task'lerine dokunmaz.
    private static func verifyWrites(
        _ provider: any TaskProviding,
        info: TaskSourceInfo,
        report: inout TaskVerificationReport,
        onUpdate: @MainActor (TaskVerificationReport) -> Void
    ) async {
        guard info.supports(.create) else {
            report.set(.create, .skipped("Not declared by the server"))
            report.set(.updateStatus, .skipped("Tested on your first status change (needs create to test safely)"))
            report.set(.delete, .skipped("Not testable without create"))
            await onUpdate(report)
            return
        }
        report.set(.create, .running)
        await onUpdate(report)
        let created: TaskItem
        do {
            created = try await provider.create(TaskDraft(title: testTaskTitle))
            report.set(.create, .passed(nil))
        } catch {
            report.set(.create, .failed(message(error)))
            report.set(.updateStatus, .skipped("Needs the test task"))
            report.set(.delete, .skipped("Needs the test task"))
            await onUpdate(report)
            return
        }
        await onUpdate(report)

        report.set(.updateStatus, .running)
        await onUpdate(report)
        do {
            let updated = try await provider.update(taskID: created.id, patch: TaskPatch(status: .inReview))
            report.set(.updateStatus, updated.status == .inReview
                ? .passed(nil)
                : .failed("PATCH returned status \"\(updated.status.rawValue)\", expected \"in_review\""))
        } catch {
            report.set(.updateStatus, .failed(message(error)))
        }
        await onUpdate(report)

        guard info.supports(.delete) else {
            report.set(.delete, .warning("The server can't delete, so the test task \"\(testTaskTitle)\" was left behind"))
            await onUpdate(report)
            return
        }
        report.set(.delete, .running)
        await onUpdate(report)
        do {
            try await provider.delete(taskID: created.id)
            report.set(.delete, .passed(nil))
        } catch {
            report.set(.delete, .failed(message(error)))
        }
        await onUpdate(report)
    }

    static func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
