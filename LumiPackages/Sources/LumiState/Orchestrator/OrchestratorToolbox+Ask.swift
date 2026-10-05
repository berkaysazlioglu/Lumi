import Foundation
import LumiKit

/// `ask_project` (karar 114 Faz 5): salt-okunur olduğu için onay istemez —
/// tek bedeli token'dır ve servis kendi bütçe tavanını taşır.
extension OrchestratorToolbox {
    func askProject(_ args: [String: Any]) async -> OrchestratorToolResult {
        guard let path = (args["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return .failure("path is required.")
        }
        let question = (args["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !question.isEmpty else { return .failure("question is required.") }
        guard let location = resolveCheckout(path) else {
            return .failure("Unknown checkout path \"\(path)\". Use a checkout path from list_projects.")
        }
        guard let projectAsker else { return .failure("ask_project is not available in this build.") }
        do {
            let answer = try await projectAsker.ask(projectPath: path, question: question)
            return OrchestratorToolResult(text: answer.text + "\n\n" + Self.footer(answer, location: location))
        } catch {
            let detail = (error as? LumiError)?.errorDescription ?? error.localizedDescription
            return .failure(detail)
        }
    }

    /// "(ask_project · api · main · $0.08 · 34 s)" — kaynağı ve bedeli görünür.
    static func footer(_ answer: ProjectAnswer, location: Location) -> String {
        var parts = ["ask_project", location.project]
        if let checkout = location.checkout { parts.append(checkout) }
        if let cost = answer.costUSD { parts.append(String(format: "$%.2f", cost)) }
        if let seconds = answer.durationSeconds { parts.append("\(Int(seconds.rounded())) s") }
        return "(" + parts.joined(separator: " · ") + ")"
    }
}
