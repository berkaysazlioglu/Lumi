import Foundation
import LumiKit

/// Kaynakların yaşam döngüsü ve kalıcılığı (Tasks planı, Faz 2).
///
/// Kaynak kaydı (`id`, ad, tür, adres) `config.json`'ın additive `taskSources`
/// anahtarında, token Keychain'de (`com.lumi.tasks` / kaynak kimliği) durur.
/// Açılışta yalnız kayıtlar ve token'lar okunur — ağ isteği atılmaz;
/// discovery ilk tazelemede (route açılınca) yapılır.
extension TasksStore {
    public func load() async {
        guard sources.isEmpty else { return }
        for source in await config.config().taskSources {
            var token: String?
            var tokenProblem: String?
            if source.kind.needsEndpoint {
                switch await credentials.token(for: source.id) {
                case .found(let value): token = value
                case .missing: tokenProblem = "No token in the Keychain for this source"
                case .failed(let detail): tokenProblem = "Couldn't read the token from the Keychain: \(detail)"
                }
            }
            providers[source.id] = factory.makeProvider(for: source, token: token)
            sources.append(SourceState(source: source, declaredInfo: nil, phase: tokenProblem == nil ? .loading : .reconnect))
            if let tokenProblem {
                record(
                    TaskRequestFailure(kind: .unauthorized, operation: .discover, serverMessage: tokenProblem, at: now()),
                    operation: .discover, source: source.id
                )
            }
        }
        await restoreAgentLinks()
    }

    func addSource(_ source: TaskSource, provider: any TaskProviding, info: TaskSourceInfo) async {
        providers[source.id] = provider
        sources.append(SourceState(source: source, declaredInfo: nil, phase: .loading))
        await persist { $0.taskSources.append(source) }
        await loadDirectories(source.id, provider: provider, info: info)
        update(source.id) { $0.declaredInfo = info }
        await refresh(source.id)
    }

    func replaceSource(_ source: TaskSource, provider: any TaskProviding, info: TaskSourceInfo) async {
        providers[source.id] = provider
        update(source.id) {
            $0.source = source
            $0.declaredInfo = info
            $0.phase = .loading
        }
        await persist { config in
            guard let index = config.taskSources.firstIndex(where: { $0.id == source.id }) else { return }
            config.taskSources[index] = source
        }
        await loadDirectories(source.id, provider: provider, info: info)
        await refresh(source.id)
    }

    public func removeSource(_ id: TaskSourceID) {
        for key in pendingWrites.keys where key.source == id {
            pendingWrites.removeValue(forKey: key)?.timer?.cancel()
        }
        pendingWriteCount = pendingWrites.count
        for key in agentLinks.keys where key.source == id { stopAgent(key) }
        failureLog.removeAll { $0.source == id }
        let removed = state(of: id)?.source
        sources.removeAll { $0.id == id }
        entries.removeAll { $0.source == id }
        providers[id] = nil
        if filter.source == id { filter.source = nil }
        if selectedTask?.source == id { selectedTask = nil }
        Task {
            await persist { $0.taskSources.removeAll { $0.id == id } }
            if removed?.kind.needsEndpoint == true {
                try? await credentials.deleteToken(for: id)
            }
        }
    }

    public func renameSource(_ id: TaskSourceID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.source.name = trimmed }
        Task {
            await persist { config in
                guard let index = config.taskSources.firstIndex(where: { $0.id == id }) else { return }
                config.taskSources[index].name = trimmed
            }
        }
    }

    /// Kaynağın prompt şablonu (ön ek / son ek).
    public func setPromptTemplate(_ template: TaskPromptTemplate, for id: TaskSourceID) {
        update(id) { $0.source.promptTemplate = template }
        Task {
            await persist { config in
                guard let index = config.taskSources.firstIndex(where: { $0.id == id }) else { return }
                config.taskSources[index].promptTemplate = template
            }
        }
    }

    public func beginEditingPromptTemplate(_ id: TaskSourceID) {
        guard state(of: id) != nil else { return }
        editingPromptTemplate = id
    }

    /// Ajan prompt'u ve kopyalanan metin — kaynağın şablonu uygulanmış.
    public func agentPrompt(for key: TaskKey) -> String {
        guard let entry = entry(key) else { return "" }
        return TaskAgentPrompt.make(task: entry.item, includeBody: info(of: key.source)?.canRead(.body) == true, template: template(of: key.source))
    }

    public func copyPrompt(for key: TaskKey) -> String {
        guard let entry = entry(key) else { return "" }
        return TaskAgentPrompt.copyText(task: entry.item, includeBody: info(of: key.source)?.canRead(.body) == true, template: template(of: key.source))
    }

    private func template(of id: TaskSourceID) -> TaskPromptTemplate {
        state(of: id)?.source.promptTemplate ?? TaskPromptTemplate()
    }

    private func persist(_ change: @escaping @Sendable (inout AppConfig) -> Void) async {
        do {
            try await config.updateConfig(change)
        } catch {
            toasts.show(.error, title: "Couldn't save task sources", message: Self.message(error))
        }
    }
}
