import Foundation

/// `ask_project` cevabı (karar 104 Faz 5).
public struct ProjectAnswer: Sendable, Equatable {
    public let text: String
    public let costUSD: Double?
    public let durationSeconds: Double?

    public init(text: String, costUSD: Double? = nil, durationSeconds: Double? = nil) {
        self.text = text
        self.costUSD = costUSD
        self.durationSeconds = durationSeconds
    }
}

/// Bir projeyi arka planda, salt-okunur araçlarla inceleyip soruyu cevaplayan
/// yüz — `claude -p` proje kökünde (`Read`/`Glob`/`Grep`).
public protocol ProjectQuestionAnswering: Sendable {
    func ask(projectPath: String, question: String) async throws -> ProjectAnswer
}
