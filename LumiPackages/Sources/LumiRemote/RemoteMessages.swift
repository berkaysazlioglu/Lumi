import Foundation
import LumiKit

/// Browser → sunucu WS mesajları. Tek endpoint (`/ws`) kullanılır; bağlantı
/// hangi terminale ait olduğunu ilk `attach` mesajıyla bildirir.
public enum RemoteClientMessage: Equatable, Sendable {
    case attach(id: String)
    /// Ham tuş bayt'ları — client escape dizilerini kendi kodlar (↑ = ESC[A vb.).
    case input(data: String)
    /// Chat mesajı — sunucu bracketed-paste ile sarar, CR ile submit eder.
    case prompt(text: String)
}

/// Sunucu → browser WS mesajları.
public enum RemoteServerMessage: Equatable, Sendable {
    case snapshot(snapshot: TerminalScreenSnapshot, terminal: RemoteTerminalSummary)
    case exited
    case error(message: String)
}

/// WS mesajlarının JSON kodlaması. Envelope: `{"type": "...", ...}`.
public enum RemoteMessageCodec {
    private struct ClientEnvelope: Decodable {
        let type: String
        let id: String?
        let data: String?
        let text: String?
    }

    private struct ServerEnvelope: Encodable {
        let type: String
        var history: String?
        var screen: [[TerminalScreenRun]]?
        var terminal: RemoteTerminalSummary?
        var message: String?
    }

    public static func decodeClient(_ raw: String) -> RemoteClientMessage? {
        guard let data = raw.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ClientEnvelope.self, from: data) else {
            return nil
        }
        switch envelope.type {
        case "attach":
            return envelope.id.map(RemoteClientMessage.attach(id:))
        case "input":
            return envelope.data.map(RemoteClientMessage.input(data:))
        case "prompt":
            return envelope.text.map(RemoteClientMessage.prompt(text:))
        default:
            return nil
        }
    }

    public static func encodeServer(_ message: RemoteServerMessage) -> String {
        let envelope: ServerEnvelope
        switch message {
        case .snapshot(let snapshot, let terminal):
            envelope = ServerEnvelope(
                type: "snapshot",
                history: snapshot.history,
                screen: snapshot.screen,
                terminal: terminal
            )
        case .exited:
            envelope = ServerEnvelope(type: "exited")
        case .error(let message):
            envelope = ServerEnvelope(type: "error", message: message)
        }
        guard let data = try? JSONEncoder().encode(envelope),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"type":"error","message":"encoding failed"}"#
        }
        return json
    }
}
