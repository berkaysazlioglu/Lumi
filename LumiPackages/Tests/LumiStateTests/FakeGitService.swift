import Foundation
import LumiKit

/// GitServicing test ikamesi (design/00 §3 deseni). FileViewerStore'un yönlendirme
/// mantığı (metin → diff, görsel → önizleme) için gereken minimum yüzey.
actor FakeGitService: GitServicing {
    struct ImagePreviewCall: Equatable {
        let file: String
        let sha: String?
    }

    var fileContent = "# title\n"
    var branchesToReturn: [GitBranch] = []
    /// `commits` bu süre kadar askıda kalır — eşzamanlılık ölçümü için
    /// (actor reentrancy: askıdayken başka çağrılar içeri girebilir).
    var commitsDelay: Duration = .zero
    var diffToReturn = UnifiedDiff(filePath: "", isBinary: false, hunks: [])
    var previewToReturn = ImagePreview(filePath: "", before: nil, after: nil)
    var commitFilesToReturn: [CommitFile] = []

    private(set) var readFileCalls: [String] = []
    private(set) var fileDiffCalls: [String] = []
    private(set) var commitFileDiffCalls: [String] = []
    private(set) var imagePreviewCalls: [ImagePreviewCall] = []
    private(set) var commitsCallCount = 0
    private(set) var maxConcurrentCommitsCalls = 0
    private var inFlightCommitsCalls = 0

    func setCommitFiles(_ files: [CommitFile]) {
        commitFilesToReturn = files
    }

    func setPreview(_ preview: ImagePreview) {
        previewToReturn = preview
    }

    func setBranches(_ list: [GitBranch]) {
        branchesToReturn = list
    }

    func setCommitsDelay(_ delay: Duration) {
        commitsDelay = delay
    }

    func branches(repoPath: String) async -> [GitBranch] { branchesToReturn }

    func commits(repoPath: String, branch: String?) async -> [GitCommit] {
        commitsCallCount += 1
        inFlightCommitsCalls += 1
        maxConcurrentCommitsCalls = max(maxConcurrentCommitsCalls, inFlightCommitsCalls)
        if commitsDelay != .zero {
            try? await Task.sleep(for: commitsDelay)
        }
        inFlightCommitsCalls -= 1
        return []
    }

    func status(repoPath: String) async -> [GitFileChange] { [] }

    func commit(repoPath: String, message: String, files: [String]) async throws {}

    func readFile(repoPath: String, file: String) async throws -> String {
        readFileCalls.append(file)
        return fileContent
    }

    func fileDiff(repoPath: String, file: String) async throws -> UnifiedDiff {
        fileDiffCalls.append(file)
        return diffToReturn
    }

    func commitFiles(repoPath: String, sha: String) async -> [CommitFile] {
        commitFilesToReturn
    }

    func commitFileDiff(repoPath: String, sha: String, file: String) async throws -> UnifiedDiff {
        commitFileDiffCalls.append(file)
        return diffToReturn
    }

    func imagePreview(repoPath: String, file: String, sha: String?) async -> ImagePreview {
        imagePreviewCalls.append(ImagePreviewCall(file: file, sha: sha))
        return previewToReturn
    }
}
