import Foundation
import LumiKit

// MARK: - SessionMeta

/// Bir terminal oturumunun aktarım meta verisi.
struct SessionMeta {
    let id: String
    let repoName: String
    let status: String
    let title: String?
    let model: String?
    let cols: Int
    let rows: Int
    let kind: String?   // oturum türü (örn. "chat", "terminal"); Faz 2 — yoksa nil
    let provider: String?
    let lastActivityAt: Double?

    init(id: String, repoName: String, status: String,
         title: String? = nil, model: String? = nil,
         cols: Int, rows: Int, kind: String? = nil,
         provider: String? = nil, lastActivityAt: Double? = nil) {
        self.id = id
        self.repoName = repoName
        self.status = status
        self.title = title
        self.model = model
        self.cols = cols
        self.rows = rows
        self.kind = kind
        self.provider = provider
        self.lastActivityAt = lastActivityAt
    }

    func toDict() -> [String: Any] {
        var d: [String: Any] = [
            "id": id,
            "repoName": repoName,
            "status": status,
            "cols": cols,
            "rows": rows,
            "kind": kind.map { $0 as Any } ?? NSNull(),
        ]
        if let title { d["title"] = title }
        if let model { d["model"] = model }
        if let provider { d["provider"] = provider }
        if let lastActivityAt { d["lastActivityAt"] = lastActivityAt }
        return d
    }
}

// MARK: - RemoteProtocol

/// Zarf codec'i — docs/spec/50-remote-protocol.md ile birebir.
enum RemoteProtocol {
    static let version = 1

    static func envelope(type: String, payload: [String: Any]) -> Data? {
        let dict: [String: Any] = ["v": version, "type": type, "payload": payload]
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    static func decode(_ data: Data) -> (type: String, payload: [String: Any])? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              dict["v"] as? Int == version,
              let type = dict["type"] as? String,
              let payload = dict["payload"] as? [String: Any] else { return nil }
        return (type, payload)
    }

    static func decode(text: String) -> (type: String, payload: [String: Any])? {
        guard let data = text.data(using: .utf8) else { return nil }
        return decode(data)
    }

    // MARK: Encode helpers (Mac → relay)

    /// `sessions` payload: `{sessions:[SessionMeta]}` — relay welcome/sessions key.
    static func sessionsPayload(_ metas: [SessionMeta]) -> [String: Any] {
        ["sessions": metas.map { $0.toDict() }]
    }

    /// `repos` payload: `{repos:[{name,path}]}` — telefondan yeni oturum başlatma seçici.
    static func reposPayload(_ repos: [[String: String]]) -> [String: Any] {
        ["repos": repos]
    }

    /// `projects` payload: favorites tree + addable pool (Mac → phone).
    static func projectsPayload(projects: [[String: Any]], addable: [[String: String]]) -> [String: Any] {
        ["projects": projects, "addable": addable]
    }

    /// `scrollback` payload: ilk bağlantıda terminal geçmişini gönderir.
    static func scrollbackPayload(sessionId: String, seq: Int, cols: Int, rows: Int, data: Data) -> [String: Any] {
        [
            "sessionId": sessionId,
            "seq": seq,
            "cols": cols,
            "rows": rows,
            "data": data.base64EncodedString(),
        ]
    }

    /// `data` payload: canlı terminal çıktısı.
    static func dataPayload(sessionId: String, seq: Int, data: Data) -> [String: Any] {
        [
            "sessionId": sessionId,
            "seq": seq,
            "data": data.base64EncodedString(),
        ]
    }

    /// `chat` payload: bir oturumun tam mesaj listesi (snapshot).
    static func chatPayload(sessionId: String, messages: [ChatMessage]) -> [String: Any] {
        ["sessionId": sessionId, "messages": messages.map { $0.toDict() }]
    }

    /// `chat_append` payload: tail'de gelen yeni mesajlar.
    static func chatAppendPayload(sessionId: String, messages: [ChatMessage]) -> [String: Any] {
        ["sessionId": sessionId, "messages": messages.map { $0.toDict() }]
    }

    /// `chat_status` payload: bir oturumun canlı turn-status'u (Faz 2). Mac→telefon.
    static func chatStatusPayload(sessionId: String, status: ChatTurnStatus) -> [String: Any] {
        var dict = status.toDict()
        dict["sessionId"] = sessionId
        return dict
    }

    /// `prompt` payload: bir oturumun etkileşimli prompt item'ı (Faz 3). Mac→telefon.
    static func promptPayload(sessionId: String, prompt: ChatPrompt) -> [String: Any] {
        var dict = prompt.toDict()
        dict["sessionId"] = sessionId
        return dict
    }

    // MARK: Decode helpers (relay → Mac)

    /// `prompt_respond` (approval) çözer — optionId (Faz 3). Telefon→Mac.
    static func decodePromptRespond(_ payload: [String: Any]) -> (sessionId: String, itemId: String, expectedRevision: Int, optionId: String)? {
        guard let sessionId = payload["sessionId"] as? String,
              let itemId = payload["itemId"] as? String,
              let rev = payload["expectedRevision"] as? Int,
              let optionId = payload["optionId"] as? String else { return nil }
        return (sessionId, itemId, rev, optionId)
    }

    /// `prompt_respond` (question) çözer — soru başına selection (Faz 3.1). Telefon→Mac.
    static func decodePromptRespondSelections(_ payload: [String: Any]) -> (sessionId: String, itemId: String, expectedRevision: Int, selections: [AskSelection])? {
        guard let sessionId = payload["sessionId"] as? String,
              let itemId = payload["itemId"] as? String,
              let rev = payload["expectedRevision"] as? Int,
              let raw = payload["selections"] as? [[String: Any]] else { return nil }
        let selections = raw.map { d in
            AskSelection(indices: (d["indices"] as? [Int]) ?? [], other: d["other"] as? String)
        }
        return (sessionId, itemId, rev, selections)
    }

    /// `subscribe` mesajından sessionId çıkarır.
    static func decodeSubscribe(_ payload: [String: Any]) -> String? {
        payload["sessionId"] as? String
    }

    /// `input` mesajından (sessionId, data) çıkarır; base64 decode yapar.
    static func decodeInput(_ payload: [String: Any]) -> (String, Data)? {
        guard let sessionId = payload["sessionId"] as? String,
              let b64 = payload["data"] as? String,
              let data = Data(base64Encoded: b64) else { return nil }
        return (sessionId, data)
    }

    /// `subscribe` payload'ından mode; yoksa geriye-uyumlu `terminal`.
    static func decodeSubscribeMode(_ payload: [String: Any]) -> String {
        payload["mode"] as? String ?? "terminal"
    }

    /// `chat_send` çözer — telefon→Mac sohbet mesajı. sessionId ve text String olmalı.
    static func decodeChatSend(_ payload: [String: Any]) -> (sessionId: String, text: String)? {
        guard let sessionId = payload["sessionId"] as? String,
              let text = payload["text"] as? String else { return nil }
        return (sessionId, text)
    }
}

/// `press_key` sözleşmesi (protokol dokümanı): yalnız bu beş tuş.
func keySequence(for key: String) -> String? {
    switch key {
    case "1", "2", "3": return key
    case "enter": return "\r"
    case "esc": return "\u{1B}"
    default: return nil
    }
}

/// 1,2,4,8,…60 sn üstel geri çekilme.
struct ReconnectBackoff {
    private var attempt = 0
    private let capSeconds: Double = 60

    mutating func nextDelay() -> Double {
        let delay = min(pow(2, Double(attempt)), capSeconds)
        attempt += 1
        return delay
    }

    mutating func reset() { attempt = 0 }
}
