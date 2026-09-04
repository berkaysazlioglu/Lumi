import AppKit
import Foundation
import LumiKit

/// Sistem sağlığı + platform yardımcıları (design/02 §8).
///
/// Refactor 3.9: bu tip artık yalnız KOMPOZİSYONDUR — sağlık kontrolleri
/// `[any SystemCheck]`, PATH düzeltmesi `PathEnvironmentFixer`, URL açma
/// `ExternalURLOpener`, dosya işlemleri `FileSystemOperations`, klasör seçimi
/// `FolderChooser` içindedir. `SystemServicing` yüzeyi değişmedi.
public final class SystemService: SystemServicing {
    public static let commandTimeout: TimeInterval = 5

    private let checks: [any SystemCheck]
    private let pathFixer: PathEnvironmentFixer
    private let urlOpener: ExternalURLOpener
    private let fileOperations: FileSystemOperations
    private let folderChooser: FolderChooser

    /// Varsayılan kontrol seti (design/02 §8 sırası korunur): shell → PTY
    /// (yalnız smoke tester verilmişse) → claude CLI → codex CLI.
    public static func defaultChecks(
        smokeTester: (any TerminalSmokeTesting)? = nil,
        locator: any BinaryLocating = SystemBinaryLocator()
    ) -> [any SystemCheck] {
        var checks: [any SystemCheck] = [ShellCheck()]
        if let smokeTester {
            checks.append(PTYSmokeCheck(smokeTester: smokeTester))
        }
        checks += AgentProvider.allCases.map {
            AgentCLICheck(provider: $0, locator: locator, timeout: commandTimeout)
        }
        return checks
    }

    public init(
        checks: [any SystemCheck],
        pathFixer: PathEnvironmentFixer = PathEnvironmentFixer(),
        urlOpener: ExternalURLOpener = ExternalURLOpener(),
        fileOperations: FileSystemOperations = FileSystemOperations(),
        folderChooser: FolderChooser = FolderChooser()
    ) {
        self.checks = checks
        self.pathFixer = pathFixer
        self.urlOpener = urlOpener
        self.fileOperations = fileOperations
        self.folderChooser = folderChooser
    }

    /// Composition root kısayolu: varsayılan kontrol seti + varsayılan
    /// yardımcılar; yalnız gerçekten değişen bağımlılıklar verilir.
    public convenience init(
        smokeTester: (any TerminalSmokeTesting)? = nil,
        runner: any ProcessRunning = SystemProcessRunner(),
        locator: any BinaryLocating = SystemBinaryLocator(),
        opener: @escaping @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) },
        allowedRoots: @escaping @Sendable () async -> [String] = { [NSHomeDirectory()] }
    ) {
        self.init(
            checks: Self.defaultChecks(smokeTester: smokeTester, locator: locator),
            pathFixer: PathEnvironmentFixer(runner: runner),
            urlOpener: ExternalURLOpener(opener: opener),
            fileOperations: FileSystemOperations(allowedRoots: allowedRoots)
        )
    }

    // MARK: - SystemServicing

    public func fixProcessPath() async {
        await pathFixer.fix()
    }

    public func runChecks(selectedProvider: AgentProvider) async -> [SystemCheckResult] {
        let context = SystemCheckContext(selectedProvider: selectedProvider)
        var results: [SystemCheckResult] = []
        results.reserveCapacity(checks.count)
        for check in checks {
            results.append(await check.run(context: context))
        }
        return results
    }

    public func openExternal(_ url: URL) throws {
        try urlOpener.open(url)
    }

    public func trash(path: String) async throws {
        try await fileOperations.trash(path: path)
    }

    /// Sözleşme senkron (`SystemServicing`); guard kök listesini async okuduğu
    /// için gerçek iş ateşle-unut bir Task'te koşar (Finder aktivasyonu zaten
    /// fire-and-forget'tir).
    public func revealInFinder(path: String) {
        let operations = fileOperations
        Task { await operations.revealInFinder(path: path) }
    }

    @MainActor
    public func chooseFolder() async -> String? {
        await folderChooser.choose()
    }
}
