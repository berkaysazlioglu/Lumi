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
    /// Doluysa yeni kaynak eklenmez; bu kaynağın adresi/token'ı yenilenir.
    public var reconnecting: TaskSourceID?

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
        var source = TaskSource(id: flow.reconnecting ?? .make(), name: Self.defaultName(for: flow), kind: flow.kind)
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
        let token = flow.kind.needsEndpoint ? flow.token.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if let reconnecting = flow.reconnecting {
            named = TaskSource(
                id: reconnecting, name: named.name, kind: named.kind, baseURL: named.baseURL,
                promptTemplate: state(of: reconnecting)?.source.promptTemplate ?? TaskPromptTemplate()
            )
        }
        if let token {
            do {
                try await credentials.setToken(token, for: named.id)
            } catch {
                toasts.show(.error, title: "Couldn't save the token", message: "The Keychain refused the write: \(Self.message(error))")
                return
            }
        }
        connectFlow = nil
        pendingConnection = nil
        if flow.reconnecting != nil {
            await replaceSource(named, provider: provider, info: info)
            toasts.show(.success, title: "Reconnected \(named.name)")
        } else {
            await addSource(named, provider: provider, info: info)
            toasts.show(.success, title: "Connected \(named.name)")
        }
    }

    /// Token reddedilen (ya da adresi değişen) kaynağı yeniden bağlar: aynı
    /// kaynak, yeni token — task'ler ve filtreler yerinde kalır.
    public func beginReconnect(_ id: TaskSourceID) {
        guard let state = state(of: id) else { return }
        var flow = TaskConnectFlow(kind: state.source.kind, name: state.source.name, address: state.source.baseURL ?? "")
        flow.reconnecting = id
        connectFlow = flow
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
        switch await create(draft, in: form.source, provider: provider) {
        case .success(let key):
            newTaskForm = nil
            selectedTask = key
        case .failure(let failure):
            newTaskForm?.isSubmitting = false
            toasts.show(.error, title: "Couldn't create task", message: failure.summary)
        }
    }

    /// Formdan bağımsız oluşturma (telefon). Kaynak `create` beyan etmeli.
    public func createTask(_ draft: TaskDraft, in source: TaskSourceID) async -> Result<TaskKey, TaskRequestFailure> {
        guard info(of: source)?.supports(.create) == true, let provider = providers[source] else {
            return .failure(TaskRequestFailure(kind: .unsupported("creating tasks"), operation: .create))
        }
        return await create(draft, in: source, provider: provider)
    }

    private func create(_ draft: TaskDraft, in source: TaskSourceID, provider: any TaskProviding) async -> Result<TaskKey, TaskRequestFailure> {
        do {
            let item = try await provider.create(draft)
            let key = TaskKey(source: source, id: item.id)
            beginWrite(key)
            endWrite(key)
            entries.append(TaskEntry(source: source, item: item))
            return .success(key)
        } catch {
            return .failure(record(error, operation: .create, source: source))
        }
    }
}
