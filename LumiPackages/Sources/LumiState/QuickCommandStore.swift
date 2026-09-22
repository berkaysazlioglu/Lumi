import Foundation
import LumiKit
import Observation

/// Proje hızlı komutlarının listesi (karar 92).
///
/// Tek doğruluk kaynağı `config.json`'daki `projectQuickCommands`'tır; store
/// yazdıktan sonra diskteki hâli geri okur, dış değişiklikler ise
/// `update(_:)` ile (config yan etkisi) gelir.
@Observable
@MainActor
public final class QuickCommandStore {
    public private(set) var commands: [ProjectQuickCommand] = []
    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let toasts: ToastStore

    public init(config: any ConfigServicing, toasts: ToastStore) {
        self.config = config
        self.toasts = toasts
    }

    public func load() async {
        update(await config.config().projectQuickCommands)
    }

    public func update(_ commands: [ProjectQuickCommand]) {
        self.commands = commands
    }

    /// Projenin komutları, kaydedildikleri sırayla.
    public func commands(for projectPath: String) -> [ProjectQuickCommand] {
        commands.filter { $0.projectPath == projectPath }
    }

    /// Ekler ya da aynı `id`'li kaydı yerinde günceller (sıra korunur).
    @discardableResult
    public func save(_ command: ProjectQuickCommand) async -> Bool {
        guard command.isValid else { return false }
        let trimmed = {
            var copy = command
            copy.name = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }()
        return await write(failureTitle: "Command could not be saved") { config in
            if let index = config.projectQuickCommands.firstIndex(where: { $0.id == trimmed.id }) {
                config.projectQuickCommands[index] = trimmed
            } else {
                config.projectQuickCommands.append(trimmed)
            }
        }
    }

    @discardableResult
    public func delete(id: String) async -> Bool {
        await write(failureTitle: "Command could not be deleted") { config in
            config.projectQuickCommands.removeAll { $0.id == id }
        }
    }

    private func write(failureTitle: String, _ mutate: @escaping @Sendable (inout AppConfig) -> Void) async -> Bool {
        do {
            try await config.updateConfig(mutate)
            update(await config.config().projectQuickCommands)
            return true
        } catch {
            toasts.show(.error, title: failureTitle, message: error.localizedDescription)
            return false
        }
    }
}
