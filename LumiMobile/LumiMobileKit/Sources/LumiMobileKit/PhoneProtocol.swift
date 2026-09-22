import Foundation
import LumiWire

/// Messages that can arrive from the relay (phone role, terminal-mirror protocol).
public enum ServerMessage: Sendable, Equatable {
    case welcome(Welcome)
    case commandResult(CommandResult)
    case pong
    // Terminal-mirror messages
    case sessions([SessionMeta])
    case scrollback(TerminalChunk)
    case data(TerminalChunk)
    // Repo list for starting a new session from the phone
    case repos([Repo])
    // Chat-mirror messages
    case chat(sessionId: String, messages: [ChatMessage])
    case chatAppend(sessionId: String, messages: [ChatMessage])
    case chatStatus(sessionId: String, status: ChatTurnStatus)
    // Phase 3: interactive prompt
    case prompt(sessionId: String, prompt: ChatPrompt)
    // Projects tree
    case projects(ProjectsSnapshot)
}

public enum CommandAction: Sendable, Equatable {
    case sendText(sessionId: String, text: String)
    case pressKey(sessionId: String, key: String)
    case startSession(repoPath: String, personaId: String?, prompt: String, kind: String? = nil,
                      branchMode: String? = nil, branchName: String? = nil,
                      baseBranch: String? = nil, workspaceName: String? = nil)
    case listBranches(repoPath: String)
    case getHistory(sessionId: String)
    case deleteSession(sessionId: String)
    case setModel(sessionId: String, model: String)
    case addProject(path: String)
}

public struct OutgoingCommand: Sendable, Equatable {
    public let commandId: String
    public let action: CommandAction

    public init(commandId: String, action: CommandAction) {
        self.commandId = commandId
        self.action = action
    }
}

/// Envelope codec — matches docs/spec/50-remote-protocol.md exactly.
/// The incoming side is tolerant: unknown type/kind/itemType returns nil without breaking the stream.
public enum PhoneProtocol {
    public static let version = 1

    // MARK: Incoming

    public static func decodeServerMessage(_ text: String) -> ServerMessage? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              dict["v"] as? Int == version,
              let type = dict["type"] as? String,
              let payload = dict["payload"] as? [String: Any] else { return nil }

        func decodePayload<T: Decodable>(_: T.Type) -> T? {
            guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return try? JSONDecoder().decode(T.self, from: payloadData)
        }

        switch type {
        case "welcome": return decodePayload(Welcome.self).map(ServerMessage.welcome)
        case "command_result": return decodePayload(CommandResult.self).map(ServerMessage.commandResult)
        case "pong": return .pong
        case "sessions":
            struct SessionsPayload: Decodable { let sessions: [SessionMeta] }
            return decodePayload(SessionsPayload.self).map { ServerMessage.sessions($0.sessions) }
        case "scrollback": return decodeTerminalChunk(payload).map(ServerMessage.scrollback)
        case "data": return decodeTerminalChunk(payload).map(ServerMessage.data)
        case "repos":
            struct ReposPayload: Decodable { let repos: [Repo] }
            return decodePayload(ReposPayload.self).map { ServerMessage.repos($0.repos) }
        case "chat", "chat_append":
            guard let sessionId = payload["sessionId"] as? String,
                  let raw = payload["messages"] as? [[String: Any]] else { return nil }
            let messages = raw.compactMap(ChatMessage.decode)
            return type == "chat" ? .chat(sessionId: sessionId, messages: messages)
                                  : .chatAppend(sessionId: sessionId, messages: messages)
        case "chat_status":
            guard let sessionId = payload["sessionId"] as? String else { return nil }
            return .chatStatus(sessionId: sessionId, status: ChatTurnStatus.decode(payload))
        case "prompt":
            guard let sessionId = payload["sessionId"] as? String,
                  let p = ChatPrompt.decode(payload) else { return nil }
            return .prompt(sessionId: sessionId, prompt: p)
        case "projects": return decodePayload(ProjectsSnapshot.self).map(ServerMessage.projects)
        default: return nil
        }
    }

    // MARK: Terminal-mirror decoders

    static func decodeTerminalChunk(_ payload: [String: Any]) -> TerminalChunk? {
        guard let sessionId = payload["sessionId"] as? String,
              let seq = payload["seq"] as? Int,
              let b64 = payload["data"] as? String,
              let bytes = Data(base64Encoded: b64) else { return nil }
        return TerminalChunk(
            sessionId: sessionId,
            seq: seq,
            cols: payload["cols"] as? Int,
            rows: payload["rows"] as? Int,
            bytes: bytes
        )
    }

    // MARK: Terminal-mirror encoders

    public static func subscribeFrame(sessionId: String, mode: String = "terminal") -> String {
        frame(type: "subscribe", payload: ["sessionId": sessionId, "mode": mode])
    }

    public static func unsubscribeFrame(sessionId: String) -> String {
        frame(type: "unsubscribe", payload: ["sessionId": sessionId])
    }

    public static func inputFrame(sessionId: String, data: Data) -> String {
        frame(type: "input", payload: [
            "sessionId": sessionId,
            "data": data.base64EncodedString()
        ])
    }

    /// Phase 3: interactive prompt response — approval (optionId). Phone→Mac.
    public static func promptRespondFrame(sessionId: String, itemId: String, expectedRevision: Int, optionId: String) -> String {
        frame(type: "prompt_respond", payload: [
            "sessionId": sessionId, "itemId": itemId,
            "expectedRevision": expectedRevision, "optionId": optionId,
        ])
    }

    /// Phase 3.1: question response — per-question selection (indices + other). Phone→Mac.
    public static func promptRespondSelectionsFrame(sessionId: String, itemId: String, expectedRevision: Int,
                                                    selections: [(indices: [Int], other: String?)]) -> String {
        let sel = selections.map { s -> [String: Any] in
            var d: [String: Any] = ["indices": s.indices]
            if let o = s.other { d["other"] = o }
            return d
        }
        return frame(type: "prompt_respond", payload: [
            "sessionId": sessionId, "itemId": itemId,
            "expectedRevision": expectedRevision, "selections": sel,
        ])
    }

    /// Phase 2: send a user message — phone→Mac. `chat_send` frame.
    public static func chatSendFrame(sessionId: String, text: String) -> String {
        frame(type: "chat_send", payload: ["sessionId": sessionId, "text": text])
    }

    // MARK: Outgoing

    public static func helloFrame(token: String) -> String {
        frame(type: "hello", payload: ["role": "phone", "token": token])
    }

    public static func pingFrame() -> String {
        frame(type: "ping", payload: [:])
    }

    public static func registerPushFrame(deviceToken: String) -> String {
        frame(type: "register_push", payload: ["deviceToken": deviceToken])
    }

    public static func unregisterPushFrame(deviceToken: String) -> String {
        frame(type: "unregister_push", payload: ["deviceToken": deviceToken])
    }

    public static func commandFrame(_ command: OutgoingCommand) -> String {
        var payload: [String: Any] = ["commandId": command.commandId]
        switch command.action {
        case .sendText(let sessionId, let text):
            payload["action"] = "send_text"
            payload["sessionId"] = sessionId
            payload["text"] = text
        case .pressKey(let sessionId, let key):
            payload["action"] = "press_key"
            payload["sessionId"] = sessionId
            payload["key"] = key
        case .startSession(let repoPath, let personaId, let prompt, let kind,
                           let branchMode, let branchName, let baseBranch, let workspaceName):
            payload["action"] = "start_session"
            payload["repoPath"] = repoPath
            payload["prompt"] = prompt
            if let personaId { payload["personaId"] = personaId }
            if let kind { payload["kind"] = kind }
            if let branchMode { payload["branchMode"] = branchMode }
            if let branchName { payload["branchName"] = branchName }
            if let baseBranch { payload["baseBranch"] = baseBranch }
            if let workspaceName { payload["workspaceName"] = workspaceName }
        case .listBranches(let repoPath):
            payload["action"] = "list_branches"
            payload["repoPath"] = repoPath
        case .getHistory(let sessionId):
            payload["action"] = "get_history"
            payload["sessionId"] = sessionId
        case .deleteSession(let sessionId):
            payload["action"] = "delete_session"
            payload["sessionId"] = sessionId
        case .setModel(let sessionId, let model):
            payload["action"] = "set_model"
            payload["sessionId"] = sessionId
            payload["model"] = model
        case .addProject(let path):
            payload["action"] = "add_project"
            payload["path"] = path
        }
        return frame(type: "command", payload: payload)
    }

    private static func frame(type: String, payload: [String: Any]) -> String {
        let dict: [String: Any] = ["v": version, "type": type, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
