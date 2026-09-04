import Foundation
import LumiKit

/// `GitServicing` test ikamesi (design/00 §3 deseni). Dönüşler ayarlanabilir,
/// çağrılar kaydedilir; içerik operasyonları için hata enjeksiyonu vardır.
public actor FakeGitService: GitServicing {
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
    public var branchesToReturn: [GitBranch] = []
    public var commitsToReturn: [GitCommit] = []
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
    public private(set) var maxConcurrentCommitsCalls = 0
    private var inFlightCommitsCalls = 0

    public init() {}

    public func setCommitFiles(_ files: [CommitFile]) {
        commitFilesToReturn = files
    }

    public func setPreview(_ preview: ImagePreview) {
        previewToReturn = preview
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
