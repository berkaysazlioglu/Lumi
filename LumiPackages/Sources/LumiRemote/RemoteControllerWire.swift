import Foundation
import LumiKit

/// Controller tarafının tel çözümleyicisi (docs/design/08). Hub'ın yayınladığı
/// frame'ler `RemoteProtocol`'ün ürettiği biçimdedir; çözümleyici aynı modülde
/// durur ki iki taraf gidiş-dönüş testiyle (`RemoteControllerWireTests`) kilitlensin.
/// Bozuk öğe sessizce düşer — tek bir kötü kayıt bütün listeyi silmez.
enum RemoteControllerWire {
    static func hubs(_ payload: [String: Any], excluding ownHubId: String) -> [RemoteHubInfo] {
        (payload["hubs"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let id = raw["hubId"] as? String, id != ownHubId,
                  let name = raw["name"] as? String else { return nil }
            return RemoteHubInfo(
                id: id, name: name,
                isOnline: raw["online"] as? Bool ?? false,
                lastSeenAt: date(fromMillis: raw["lastSeenAt"]),
                controllerCount: raw["controllerCount"] as? Int ?? 0)
        }
    }

    static func sessions(_ payload: [String: Any]) -> [RemoteSessionInfo] {
        (payload["sessions"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let id = raw["id"] as? String else { return nil }
            return RemoteSessionInfo(
                id: id,
                title: raw["title"] as? String,
                repoName: raw["repoName"] as? String ?? "",
                status: raw["status"] as? String ?? "idle",
                provider: (raw["provider"] as? String).flatMap(AgentProvider.init(rawValue:)),
                awaitingDecision: raw["awaitingDecision"] as? Bool ?? false,
                lastActivityAt: date(fromMillis: raw["lastActivityAt"]))
        }
    }

    /// `projects` frame'inin (ya da `welcome`'ın) proje ağacı ve Other grupları.
    static func tree(_ payload: [String: Any]) -> (projects: [RemoteProjectNode], others: [RemoteOtherGroup]) {
        let projects = (payload["projects"] as? [[String: Any]] ?? []).compactMap { raw -> RemoteProjectNode? in
            guard let path = raw["path"] as? String, let name = raw["name"] as? String else { return nil }
            let appearance = raw["appearance"] as? [String: String]
            return RemoteProjectNode(
                path: path, name: name,
                checkouts: (raw["checkouts"] as? [[String: Any]] ?? []).compactMap(checkout),
                color: appearance?["color"], icon: appearance?["icon"])
        }
        let others = (payload["others"] as? [[String: Any]] ?? []).compactMap { raw -> RemoteOtherGroup? in
            guard let path = raw["path"] as? String else { return nil }
            return RemoteOtherGroup(
                path: path, label: raw["label"] as? String ?? (path as NSString).lastPathComponent,
                agentIds: raw["agentIds"] as? [String] ?? [])
        }
        return (projects, others)
    }

    private static func checkout(_ raw: [String: Any]) -> RemoteCheckoutNode? {
        guard let path = raw["path"] as? String else { return nil }
        return RemoteCheckoutNode(
            path: path,
            title: raw["title"] as? String ?? (path as NSString).lastPathComponent,
            kind: raw["kind"] as? String ?? "root",
            branch: raw["branch"] as? String,
            agentIds: raw["agentIds"] as? [String] ?? [])
    }

    /// `scrollback` (snapshot) ya da `data` frame'i → oturum kimliği + parça.
    static func terminalChunk(type: String, payload: [String: Any]) -> (sessionId: String, chunk: RemoteTerminalChunk)? {
        guard type == "scrollback" || type == "data",
              let sessionId = payload["sessionId"] as? String,
              let encoded = payload["data"] as? String,
              let data = Data(base64Encoded: encoded) else { return nil }
        let isSnapshot = type == "scrollback"
        return (sessionId, RemoteTerminalChunk(
            data: data,
            cols: isSnapshot ? payload["cols"] as? Int : nil,
            rows: isSnapshot ? payload["rows"] as? Int : nil,
            isSnapshot: isSnapshot))
    }

    struct CommandReply {
        let commandId: String
        let ok: Bool
        let error: String?
        let sessionId: String?
    }

    static func commandReply(_ payload: [String: Any]) -> CommandReply? {
        guard let commandId = payload["commandId"] as? String else { return nil }
        return CommandReply(
            commandId: commandId, ok: payload["ok"] as? Bool ?? false,
            error: payload["error"] as? String, sessionId: payload["sessionId"] as? String)
    }

    // MARK: - Controller → hub

    static func startSessionCommand(
        commandId: String, checkoutPath: String, kind: RemoteSessionKind, prompt: String = ""
    ) -> [String: Any] {
        var payload: [String: Any] = ["commandId": commandId, "action": "start_session", "repoPath": checkoutPath, "prompt": prompt]
        switch kind {
        case .claude(let model):
            // `chat` türü Mac'te bir claude TERMİNALİ açar ve kimliğini döner (karar 89).
            payload["kind"] = "chat"
            if let model { payload["model"] = model.rawValue }
        case .shell:
            payload["kind"] = "shell"
        }
        return payload
    }

    static func sendTextCommand(commandId: String, sessionId: String, text: String) -> [String: Any] {
        ["commandId": commandId, "action": "send_text", "sessionId": sessionId, "text": text]
    }

    /// `chat` frame'i → oturum kimliği + mesajlar (`ChatMessage.decode`; bozuk mesaj düşer).
    static func chatSnapshot(_ payload: [String: Any]) -> (sessionId: String, messages: [ChatMessage])? {
        guard let sessionId = payload["sessionId"] as? String else { return nil }
        let messages = (payload["messages"] as? [[String: Any]] ?? []).compactMap(ChatMessage.decode)
        return (sessionId, messages)
    }

    static func deleteSessionCommand(commandId: String, sessionId: String) -> [String: Any] {
        ["commandId": commandId, "action": "delete_session", "sessionId": sessionId]
    }

    private static func date(fromMillis value: Any?) -> Date? {
        guard let millis = (value as? Double) ?? (value as? Int).map(Double.init) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
