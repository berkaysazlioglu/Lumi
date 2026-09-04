import Foundation
import LumiKit

/// `SystemServicing` fake'i. Protokol `Sendable` (izolasyonsuz) olduğundan
/// kayıt bir kilitle korunur; `chooseFolder` MainActor'da çağrılır.
public final class FakeSystemService: SystemServicing, @unchecked Sendable {
    private let lock = NSLock()

    // MARK: Ayarlanabilir dönüşler
    private var checkResults: [SystemCheckResult] = []
    private var folderToChoose: String?
    private var openExternalError: LumiError?
    private var trashError: LumiError?

    // MARK: Çağrı kaydı
    private var runChecksProviders: [AgentProvider] = []
    private var fixProcessPathCalls = 0
    private var openedURLs: [URL] = []
    private var trashedPaths: [String] = []
    private var revealedPaths: [String] = []
    private var chooseFolderCalls = 0

    public init() {}

    // MARK: Ayarlama
    public func setCheckResults(_ results: [SystemCheckResult]) {
        lock.withLock { checkResults = results }
    }

    public func setFolderToChoose(_ path: String?) {
        lock.withLock { folderToChoose = path }
    }

    public func setOpenExternalError(_ error: LumiError?) {
        lock.withLock { openExternalError = error }
    }

    public func setTrashError(_ error: LumiError?) {
        lock.withLock { trashError = error }
    }

    // MARK: Kayıt okuma
    public var runChecksCalls: [AgentProvider] { lock.withLock { runChecksProviders } }
    public var fixProcessPathCallCount: Int { lock.withLock { fixProcessPathCalls } }
    public var openedExternalURLs: [URL] { lock.withLock { openedURLs } }
    public var trashCalls: [String] { lock.withLock { trashedPaths } }
    public var revealCalls: [String] { lock.withLock { revealedPaths } }
    public var chooseFolderCallCount: Int { lock.withLock { chooseFolderCalls } }

    // MARK: SystemServicing
    public func runChecks(selectedProvider: AgentProvider) async -> [SystemCheckResult] {
        lock.withLock {
            runChecksProviders.append(selectedProvider)
            return checkResults
        }
    }

    public func fixProcessPath() async {
        lock.withLock { fixProcessPathCalls += 1 }
    }

    public func openExternal(_ url: URL) throws {
        let error: LumiError? = lock.withLock {
            openedURLs.append(url)
            return openExternalError
        }
        if let error { throw error }
    }

    public func trash(path: String) async throws {
        let error: LumiError? = lock.withLock {
            trashedPaths.append(path)
            return trashError
        }
        if let error { throw error }
    }

    public func revealInFinder(path: String) {
        lock.withLock { revealedPaths.append(path) }
    }

    @MainActor
    public func chooseFolder() async -> String? {
        lock.withLock {
            chooseFolderCalls += 1
            return folderToChoose
        }
    }
}
