import Foundation
import LumiKit

/// Doğrulanmış HTTP isteğini hook olayına çeviren saf yönlendirici (karar 45).
/// Sunucudan bağımsız test edilir: yol, yöntem, token ve terminal başlığı.
enum AgentHookRequestRouter {
    enum Disposition: Equatable, Sendable {
        case accepted(AgentHookEvent)
        case rejected(status: Int, reason: String)
    }

    static let tokenHeader = "X-Lumi-Agent-Hook-Token"
    static let terminalHeader = "X-Lumi-Terminal-ID"
    static let pathPrefix = "/hook/"

    static func route(_ request: HTTPRequest, token: String, now: Date = Date()) -> Disposition {
        guard request.method == "POST" else {
            return .rejected(status: 405, reason: "Method Not Allowed")
        }
        guard request.path.hasPrefix(pathPrefix),
              let provider = AgentProvider(rawValue: String(request.path.dropFirst(pathPrefix.count))) else {
            return .rejected(status: 404, reason: "Not Found")
        }
        // Sabit-zamanlı karşılaştırma gerekmez: loopback + rastgele 192-bit sır;
        // saldırı yüzeyi aynı kullanıcı hesabındaki süreçlerle sınırlı.
        guard request.header(tokenHeader) == token else {
            return .rejected(status: 401, reason: "Unauthorized")
        }
        guard let rawID = request.header(terminalHeader), let uuid = UUID(uuidString: rawID) else {
            return .rejected(status: 400, reason: "Bad Request")
        }
        guard let event = AgentHookEvent.parse(
            provider: provider,
            terminalID: TerminalID(raw: uuid),
            body: request.body,
            receivedAt: now
        ) else {
            return .rejected(status: 400, reason: "Bad Request")
        }
        return .accepted(event)
    }
}
