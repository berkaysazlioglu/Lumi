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
    /// Claude'un script yazdığı taslakların kimlikleri (karar 92).
    public private(set) var generatingIDs: Set<String> = []
    @ObservationIgnored private let config: any ConfigServicing
    @ObservationIgnored private let generator: any QuickCommandGenerating
    @ObservationIgnored private let scripts: any QuickCommandScriptWriting
    @ObservationIgnored private let launcher: any QuickCommandBackgroundLaunching
    @ObservationIgnored private let toasts: ToastStore

    public init(
        config: any ConfigServicing, generator: any QuickCommandGenerating,
        scripts: any QuickCommandScriptWriting, launcher: any QuickCommandBackgroundLaunching,
        toasts: ToastStore
    ) {
        self.config = config
        self.generator = generator
        self.scripts = scripts
        self.launcher = launcher
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

    /// Projenin `Start App` komutu (karar 93) — kayıtlıysa gövdesi doludur.
    public func startApp(for projectPath: String) -> ProjectQuickCommand? {
        commands.first { $0.projectPath == projectPath && $0.role == .startApp }
    }

    /// Checkout menüsünün `Actions` alt menüsündeki komutlar.
    public func actions(for projectPath: String) -> [ProjectQuickCommand] {
        commands(for: projectPath).filter { $0.role == .action }
    }

    /// Ekler ya da aynı `id`'li kaydı yerinde günceller (sıra korunur).
    /// Karar 93: gövdesi boşaltılmış `Start App` kaydedilmez, SİLİNİR — boş
    /// Start App menüde görünmez; projede ikinci bir Start App de oluşmaz.
    @discardableResult
    public func save(_ command: ProjectQuickCommand) async -> Bool {
        if command.role == .startApp, command.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return await write(failureTitle: "Start App could not be cleared") { config in
                config.projectQuickCommands.removeAll { $0.projectPath == command.projectPath && $0.role == .startApp }
            }
        }
        guard command.isValid else { return false }
        let trimmed = {
            var copy = command
            copy.name = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }()
        return await write(failureTitle: "Command could not be saved") { config in
            if trimmed.role == .startApp {
                config.projectQuickCommands.removeAll {
                    $0.projectPath == trimmed.projectPath && $0.role == .startApp && $0.id != trimmed.id
                }
            }
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

    /// Komutu checkout'a göre çözüp script dosyasına yazar ve terminale
    /// girilecek satırı döner; yazılamazsa toast gösterip nil döner.
    public func prepareRun(_ command: ProjectQuickCommand, context: QuickCommandContext) async -> String? {
        let fileName = QuickCommandRun.fileName(commandID: command.id, checkoutName: context.name)
        let contents = QuickCommandRun.scriptContents(command, context: context)
        var line: String?
        await toasts.reporting {
            let path = try await self.scripts.writeScript(named: fileName, contents: contents)
            line = QuickCommandRun.launchLine(scriptPath: path)
        }
        return line
    }

    /// Karar 93: komutu terminal açmadan arka planda başlatır; çıktı script'in
    /// yanındaki `.log` dosyasına gider. Başarıda log yolunu döner.
    public func launchInBackground(_ command: ProjectQuickCommand, context: QuickCommandContext) async -> String? {
        let fileName = QuickCommandRun.fileName(commandID: command.id, checkoutName: context.name)
        let contents = QuickCommandRun.scriptContents(command, context: context)
        var logPath: String?
        await toasts.reporting {
            let path = try await self.scripts.writeScript(named: fileName, contents: contents)
            let log = QuickCommandRun.logPath(scriptPath: path)
            try await self.launcher.launch(scriptPath: path, workingDirectory: context.path, logPath: log)
            logPath = log
        }
        return logPath
    }

    public func isGenerating(_ draftID: String) -> Bool {
        generatingIDs.contains(draftID)
    }

    /// Taslak için Claude'dan script ister. Aynı taslak için ikinci istek
    /// uçuştaki bitmeden başlamaz (nil döner); hata toast olarak görünür.
    /// Sonuç KAYDEDİLMEZ — kullanıcı script'i görüp Save'e basar.
    public func generate(draftID: String, request: QuickCommandGenerationRequest) async -> String? {
        guard !generatingIDs.contains(draftID) else { return nil }
        generatingIDs.insert(draftID)
        defer { generatingIDs.remove(draftID) }

        var script: String?
        await toasts.reporting {
            script = try await self.generator.generate(request)
        }
        return script
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
