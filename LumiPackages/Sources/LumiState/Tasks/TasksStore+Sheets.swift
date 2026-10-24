import Foundation
import LumiKit

/// Bağlama sheet'inin durumu: adapter seçimi → (custom'da adres + token) →
/// Verify → Connect.
public struct TaskConnectFlow: Sendable {
    public var kind: TaskProviderKind
    public var name: String
    public var address: String
    public var token: String
    public var report: TaskVerificationReport?
    public var isVerifying = false
    /// Adres doğrulamasının hatası (Verify'a basılınca dolar).
    public var addressProblem: String?

    public init(kind: TaskProviderKind = .custom, name: String = "", address: String = "", token: String = "") {
        self.kind = kind
        self.name = name
        self.address = address
        self.token = token
    }

    /// Verify'a basılabilir mi.
    public var canVerify: Bool {
        guard kind.isAvailable, !isVerifying else { return false }
        guard kind.needsEndpoint else { return true }
        return !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var canConnect: Bool { report?.canConnect == true && !isVerifying }
}

/// Yeni task sheet'inin durumu.
public struct NewTaskForm: Sendable {
    public var source: TaskSourceID
    public var title = ""
    public var body = ""
    public var status: TaskStatus = .todo
    public var projectKey: String?
    public var priority: TaskPriority = .none
    public var assignee: TaskUser?
    public var isSubmitting = false

    public init(source: TaskSourceID) {
        self.source = source
    }

    public var canSubmit: Bool {
        !isSubmitting && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension TasksStore {
    // MARK: - Bağlama

    public func beginConnect() {
        connectFlow = TaskConnectFlow()
    }

    public func cancelConnect() {
        connectFlow = nil
    }

    /// Adapter seçimi değişince önceki Verify sonucu geçersizdir.
    public func selectConnectKind(_ kind: TaskProviderKind) {
        guard kind.isAvailable, connectFlow?.kind != kind else { return }
        connectFlow?.kind = kind
        connectFlow?.report = nil
        connectFlow?.addressProblem = nil
    }

    /// Adres/token düzenlenince eski Verify sonucu da düşer.
    public func connectInputsChanged() {
        connectFlow?.report = nil
        connectFlow?.addressProblem = nil
    }

    public func verifyConnect() async {
        guard var flow = connectFlow, flow.canVerify else { return }
        var source = TaskSource(name: Self.defaultName(for: flow), kind: flow.kind)
        if flow.kind.needsEndpoint {
            switch TaskEndpoint.normalize(flow.address) {
            case .failure(let problem):
                connectFlow?.addressProblem = problem.message
                return
            case .success(let url):
                source.baseURL = url.absoluteString
            }
        }
        flow.isVerifying = true
        flow.addressProblem = nil
        flow.report = TaskVerificationReport()
        connectFlow = flow
        let token = flow.kind.needsEndpoint ? flow.token.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let provider = factory.makeProvider(for: source, token: token)
        let report = await TaskSourceVerifier.run(provider) { [weak self] report in
            self?.connectFlow?.report = report
        }
        guard connectFlow != nil else { return }
        connectFlow?.report = report
        connectFlow?.isVerifying = false
        pendingConnection = report.canConnect ? (source, provider) : nil
    }

    public func finishConnect() async {
        guard let flow = connectFlow, flow.canConnect, let info = flow.report?.info,
              let (source, provider) = pendingConnection
        else { return }
        var named = source
        named.name = Self.defaultName(for: flow, info: info)
        connectFlow = nil
        pendingConnection = nil
        await addSource(named, provider: provider, info: info)
        toasts.show(.success, title: "Connected \(named.name)")
    }

    static func defaultName(for flow: TaskConnectFlow, info: TaskSourceInfo? = nil) -> String {
        let typed = flow.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let name = info?.name, !name.isEmpty { return name }
        if flow.kind.needsEndpoint, case .success(let url) = TaskEndpoint.normalize(flow.address), let host = url.host {
            return host
        }
        return flow.kind.title
    }

    // MARK: - Yeni task

    /// `create` destekleyen kaynaklar — filtre bir kaynağa daraltılmışsa yalnız o.
    public var creatableSources: [SourceState] {
        visibleSources.filter { $0.info?.supports(.create) == true && $0.phase == .ready }
    }

    public func beginNewTask(status: TaskStatus = .todo) {
        guard let source = creatableSources.first else { return }
        var form = NewTaskForm(source: source.id)
        form.status = status
        if let projectKey = filter.projectKey { form.projectKey = projectKey }
        newTaskForm = form
    }

    public func cancelNewTask() {
        newTaskForm = nil
    }

    /// Kaynak değişince kaynağa ait seçimler (proje, kişi) sıfırlanır.
    public func selectNewTaskSource(_ id: TaskSourceID) {
        guard newTaskForm?.source != id else { return }
        newTaskForm?.source = id
        newTaskForm?.projectKey = nil
        newTaskForm?.assignee = nil
    }

    public func submitNewTask() async {
        guard var form = newTaskForm, form.canSubmit,
              let info = info(of: form.source), info.supports(.create),
              let provider = providers[form.source]
        else { return }
        form.isSubmitting = true
        newTaskForm = form
        let body = form.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = TaskDraft(
            title: form.title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: info.canWrite(.body) && !body.isEmpty ? body : nil,
            status: form.status,
            projectKey: info.canWrite(.project) ? form.projectKey : nil,
            priority: info.canWrite(.priority) && form.priority != .none ? form.priority : nil,
            assignee: info.canAssign ? form.assignee : nil
        )
        do {
            let item = try await provider.create(draft)
            let key = TaskKey(source: form.source, id: item.id)
            beginWrite(key)
            endWrite(key)
            entries.append(TaskEntry(source: form.source, item: item))
            newTaskForm = nil
            selectedTask = key
        } catch {
            newTaskForm?.isSubmitting = false
            report(error, title: "Couldn't create task")
        }
    }
}
