import Foundation
import LumiKit

struct PlasticWorkspaceMetadata {
    let revision: String
    let repository: String
    let branch: String

    init(header: String, selector: String) throws {
        // cm 11's --machinereadable header is STATUS|changeset|repository|server.
        guard let line = header.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("STATUS|") }) else {
            throw WorkspaceFailure("Plastic returned an unsupported workspace status header.")
        }
        let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, Int64(fields[1]) != nil, !fields[2].isEmpty, !fields[3].isEmpty else {
            throw WorkspaceFailure("Plastic workspace status is incomplete.")
        }
        revision = fields[1]
        repository = "\(fields[2])@\(fields[3])"
        let branches = selector.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard ["smartbranch ", "branch ", "br "].contains(where: value.hasPrefix) else { return nil }
            let quoted = value.split(separator: "\"", omittingEmptySubsequences: false)
            return quoted.count >= 3 ? String(quoted[1]) : nil
        }
        guard branches.count <= 1 else { throw WorkspaceFailure("Multi-branch Plastic selectors are not supported for workspace creation.") }
        branch = branches.first ?? "/main"
    }
}
