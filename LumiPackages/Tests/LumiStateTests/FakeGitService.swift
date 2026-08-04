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
    var diffToReturn = UnifiedDiff(filePath: "", isBinary: false, hunks: [])
    var previewToReturn = ImagePreview(filePath: "", before: nil, after: nil)
    var commitFilesToReturn: [CommitFile] = []

    private(set) var readFileCalls: [String] = []
    private(set) var fileDiffCalls: [String] = []
    private(set) var commitFileDiffCalls: [String] = []
    private(set) var imagePreviewCalls: [ImagePreviewCall] = []

    func setCommitFiles(_ files: [CommitFile]) {
        commitFilesToReturn = files
    }

    func setPreview(_ preview: ImagePreview) {
        previewToReturn = preview
    }

    func branches(repoPath: String) async -> [GitBranch] { [] }

    func commits(repoPath: String, branch: String?) async -> [GitCommit] { [] }

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
