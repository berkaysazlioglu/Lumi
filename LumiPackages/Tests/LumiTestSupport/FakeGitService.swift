import Foundation
import LumiKit

/// Git yüzeyinin test ikamesi (design/00 §3 deseni): üç dar protokolü de
/// (`GitReading`/`GitContentReading`/`GitWriting`) uygular, böylece hem tam
/// `GitServicing` bekleyen hem de tek yüzey bekleyen tüketicilere verilebilir. Dönüşler ayarlanabilir,
/// çağrılar kaydedilir; içerik operasyonları için hata enjeksiyonu vardır.
public actor FakeGitService: GitReading, GitContentReading, GitWriting {
    public struct ImagePreviewCall: Equatable, Sendable {
        public let file: String
        public let sha: String?

        public init(file: String, sha: String?) {
            self.file = file
            self.sha = sha
        }
    }

    public struct CommitCall: Equatable, Sendable {
        public let repoPath: String
        public let message: String
        public let files: [String]

        public init(repoPath: String, message: String, files: [String]) {
            self.repoPath = repoPath
            self.message = message
            self.files = files
        }
    }

    // MARK: Ayarlanabilir dönüşler
    public var fileContent = "# title\n"
    /// `readFile` gecikmesi (yarış senaryoları).
    public var readFileDelay: Duration = .zero
    public var branchesToReturn: [GitBranch] = []
    public var commitsToReturn: [GitCommit] = []
    /// `history(repoPath:limit:)` dönüşü — graph'lı History sekmesi.
    public var historyToReturn: [GitCommit] = []
    public var remoteURLToReturn: String?
    public var isGitHubCLIInstalled = true
    public var branchSummaryToReturn: GitBranchSummary?
    public var statusToReturn: [GitFileChange] = []
    /// `commits` bu süre kadar askıda kalır — eşzamanlılık ölçümü için
    /// (actor reentrancy: askıdayken başka çağrılar içeri girebilir).
    public var commitsDelay: Duration = .zero
    public var diffToReturn = UnifiedDiff(filePath: "", isBinary: false, hunks: [])
    public var previewToReturn = ImagePreview(filePath: "", before: nil, after: nil)
    public var commitFilesToReturn: [CommitFile] = []
    /// Fırlatan operasyonların (readFile/diff'ler/commit) ortak hata enjeksiyonu.
    public var errorToThrow: LumiError?

    // MARK: Çağrı kaydı
    public private(set) var readFileCalls: [String] = []
    public private(set) var fileDiffCalls: [String] = []
    public private(set) var commitFileDiffCalls: [String] = []
    public private(set) var imagePreviewCalls: [ImagePreviewCall] = []
    public private(set) var commitCalls: [CommitCall] = []
    public private(set) var branchesCallCount = 0
    public private(set) var statusCallCount = 0
    public private(set) var commitsCallCount = 0
    public private(set) var historyCalls: [Int] = []
    public private(set) var maxConcurrentCommitsCalls = 0
    private var inFlightCommitsCalls = 0

    public init() {}

    public func setCommitFiles(_ files: [CommitFile]) {
        commitFilesToReturn = files
    }

    public func setPreview(_ preview: ImagePreview) {
        previewToReturn = preview
    }

    /// `readFile` bu süre kadar askıda kalır — geç dönen yüklemenin yeni bir
    /// sunumu ezmediğini doğrulamak için (FileViewerStore yarış koruması).
    public func setReadFileDelay(_ delay: Duration) {
        readFileDelay = delay
    }

    public func setBranches(_ list: [GitBranch]) {
        branchesToReturn = list
    }

    public func setCommits(_ list: [GitCommit]) {
        commitsToReturn = list
    }

    public func setStatus(_ list: [GitFileChange]) {
        statusToReturn = list
    }

    public func setHistory(_ list: [GitCommit]) {
        historyToReturn = list
    }

    public func setRemoteURL(_ url: String?) {
        remoteURLToReturn = url
    }

    public func setGitHubCLIInstalled(_ installed: Bool) {
        isGitHubCLIInstalled = installed
    }

    public func setDiff(_ diff: UnifiedDiff) {
        diffToReturn = diff
    }

    public func setFileContent(_ content: String) {
        fileContent = content
    }

    public func setCommitsDelay(_ delay: Duration) {
        commitsDelay = delay
    }

    public func setError(_ error: LumiError?) {
        errorToThrow = error
    }

    public func branches(repoPath: String) async -> [GitBranch] {
        branchesCallCount += 1
        return branchesToReturn
    }

    public func commits(repoPath: String, branch: String?) async -> [GitCommit] {
        commitsCallCount += 1
        inFlightCommitsCalls += 1
        maxConcurrentCommitsCalls = max(maxConcurrentCommitsCalls, inFlightCommitsCalls)
        if commitsDelay != .zero {
            try? await Task.sleep(for: commitsDelay)
        }
        inFlightCommitsCalls -= 1
        return commitsToReturn
    }

    public func history(repoPath: String, limit: Int) async -> [GitCommit] {
        historyCalls.append(limit)
        return historyToReturn
    }

    public func remoteURL(repoPath: String) async -> String? {
        remoteURLToReturn
    }

    public func isGitHubCLIAvailable() async -> Bool {
        isGitHubCLIInstalled
    }

    public func setBranchSummary(_ summary: GitBranchSummary?) {
        branchSummaryToReturn = summary
    }

    public func branchSummary(repoPath: String) async -> GitBranchSummary? {
        branchSummaryToReturn
    }

    /// `workingTreeDiffText` dönüşü (karar 46).
    public var diffTextToReturn = ""
    public private(set) var diffTextCalls: [[String]] = []

    public func setDiffText(_ text: String) { diffTextToReturn = text }

    public func workingTreeDiffText(repoPath: String, files: [String]) async -> String {
        diffTextCalls.append(files)
        return diffTextToReturn
    }

    public func status(repoPath: String) async -> [GitFileChange] {
        statusCallCount += 1
        return statusToReturn
    }

    public func commit(repoPath: String, message: String, files: [String]) async throws {
        commitCalls.append(CommitCall(repoPath: repoPath, message: message, files: files))
        if let errorToThrow { throw errorToThrow }
    }

    public func readFile(repoPath: String, file: String) async throws -> String {
        readFileCalls.append(file)
        if readFileDelay > .zero { try? await Task.sleep(for: readFileDelay) }
        if let errorToThrow { throw errorToThrow }
        return fileContent
    }

    public func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff {
        fileDiffCalls.append(file)
        if let errorToThrow { throw errorToThrow }
        return diffToReturn
    }

    public func commitFiles(repoPath: String, sha: String) async -> [CommitFile] {
        commitFilesToReturn
    }

    public func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff {
        commitFileDiffCalls.append(file)
        if let errorToThrow { throw errorToThrow }
        return diffToReturn
    }

    public func imagePreview(repoPath: String, file: String, sha: String?) async -> ImagePreview {
        imagePreviewCalls.append(ImagePreviewCall(file: file, sha: sha))
        return previewToReturn
    }
}
