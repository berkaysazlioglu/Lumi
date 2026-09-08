import Darwin
import Foundation
import LumiKit

/// Copies Unity's regenerable Library cache without sharing filesystem links.
/// The copy is staged inside the already-created workspace and installed with
/// one move, so a failed copy cannot replace an existing Library.
public struct UnityLibraryCopier: Sendable {
    public init() {}

    public func blockedReason(sourcePath: String) -> String? {
        let library = URL(fileURLWithPath: sourcePath).appendingPathComponent("Library")
        guard isDirectory(library) else { return "Library is unavailable" }
        let temp = URL(fileURLWithPath: sourcePath).appendingPathComponent("Temp")
        if FileManager.default.fileExists(atPath: temp.appendingPathComponent("UnityLockfile").path) {
            return "A Unity lock file exists. Close the source Editor or turn off Copy Library."
        }
        let lock = library.appendingPathComponent("UnityLockfile")
        if FileManager.default.fileExists(atPath: lock.path) { return "Unity appears active (Library/UnityLockfile exists)" }
        let instance = library.appendingPathComponent("EditorInstance.json")
        guard let data = try? Data(contentsOf: instance),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let pid = (object["processID"] as? NSNumber)?.int32Value ?? (object["pid"] as? NSNumber)?.int32Value ?? 0
        guard pid > 0, kill(pid, 0) == 0 else { return nil }
        return "Unity appears active (EditorInstance.json reports process \(pid))"
    }

    public func copy(sourcePath: String, workspacePath: String) async throws {
        let fm = FileManager.default
        let sourceRoot = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let workspaceRoot = URL(fileURLWithPath: workspacePath).standardizedFileURL
        let source = sourceRoot.appendingPathComponent("Library")
        let target = workspaceRoot.appendingPathComponent("Library")
        guard isDirectory(sourceRoot), isDirectory(workspaceRoot), isDirectory(source) else {
            throw WorkspaceFailure("Unity Library source and workspace must be existing directories")
        }
        guard !isSymlink(sourceRoot), !isSymlink(source), !isSymlink(workspaceRoot), !isSymlink(target) else {
            throw WorkspaceFailure("Unity Library and workspace roots cannot be symbolic links")
        }
        let sourcePathCanonical = sourceRoot.resolvingSymlinksInPath().path
        let workspacePathCanonical = workspaceRoot.resolvingSymlinksInPath().path
        guard sourcePathCanonical != workspacePathCanonical,
              !workspacePathCanonical.hasPrefix(sourcePathCanonical + "/"),
              !sourcePathCanonical.hasPrefix(workspacePathCanonical + "/") else {
            throw WorkspaceFailure("Unity Library destination cannot be the source or inside it")
        }
        guard !fm.fileExists(atPath: target.path) else { throw WorkspaceFailure("Destination Library already exists") }
        if let reason = blockedReason(sourcePath: sourcePath) { throw WorkspaceFailure(reason) }

        let staging = workspaceRoot.appendingPathComponent(".lumi-library-staging-\(UUID().uuidString)")
        var ownsStaging = false
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            ownsStaging = true
            try await Task.detached(priority: .utility) {
                try Self.copyDirectory(source: source, destination: staging)
            }.value
            guard !fm.fileExists(atPath: target.path) else {
                throw WorkspaceFailure("Destination Library already exists")
            }
            try fm.moveItem(at: staging, to: target)
        } catch {
            if ownsStaging { try? fm.removeItem(at: staging) }
            throw error
        }
    }

    private static func copyDirectory(source: URL, destination: URL) throws {
        let fm = FileManager.default
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], options: []) {
            try autoreleasepool {
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw WorkspaceFailure("Unity Library contains a symbolic link: \(item.lastPathComponent)") }
                if values.isDirectory == true {
                    if item.lastPathComponent == "Temp" || item.lastPathComponent == "Logs" { return }
                    let child = destination.appendingPathComponent(item.lastPathComponent)
                    try fm.createDirectory(at: child, withIntermediateDirectories: false)
                    try copyDirectory(source: item, destination: child)
                } else if values.isRegularFile == true {
                    try fm.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
                }
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
