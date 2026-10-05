import Foundation
import LumiKit

/// MCP Streamable HTTP'nin Lumi'nin ihtiyacı kadarı (karar 114): tek uç
/// (`POST /mcp`), yalnız JSON yanıt (SSE yok — `GET` 405 döner, istemci
/// akışsız devam eder), oturum başlığı yok. Saf yönlendirici: HTTP isteğini
/// yanıta ya da araç çağrısına çevirir, sunucudan bağımsız test edilir.
enum MCPRequestRouter {
    /// JSON-RPC istek kimliği — sayı ya da metin olabilir, aynen geri yazılır.
    enum RequestID: Equatable, Sendable {
        case number(Int)
        case string(String)

        init?(_ raw: Any?) {
            if let value = raw as? String {
                self = .string(value)
            } else if let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
                self = .number(value.intValue)
            } else {
                return nil
            }
        }

        var json: Any {
            switch self {
            case .number(let value): return value
            case .string(let value): return value
            }
        }
    }

    enum Disposition: Equatable, Sendable {
        /// Hazır HTTP yanıtı (`body` nil = gövdesiz).
        case reply(status: Int, body: Data?)
        /// Yürütücüye gidecek `tools/call`.
        case callTool(id: RequestID, name: String, arguments: Data)
    }

    static let path = "/mcp"
    /// İstemci sürüm söylemezse önerilen protokol sürümü.
    static let fallbackProtocolVersion = "2025-06-18"

    enum ErrorCode {
        static let parse = -32700
        static let invalidRequest = -32600
        static let methodNotFound = -32601
        static let invalidParams = -32602
    }

    static func route(_ request: HTTPRequest, token: String, serverVersion: String) -> Disposition {
        guard request.path.split(separator: "?").first.map(String.init) == path else {
            return .reply(status: 404, body: nil)
        }
        // Aynı kullanıcı hesabındaki başka süreçler araç çağıramasın.
        guard request.header("Authorization") == "Bearer \(token)" else {
            return .reply(status: 401, body: nil)
        }
        // SSE akışı ve oturum silme desteklenmez (spec: 405 serbest).
        guard request.method == "POST" else {
            return .reply(status: 405, body: nil)
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body),
              let message = object as? [String: Any] else {
            return .reply(status: 400, body: error(id: nil, code: ErrorCode.parse, message: "Parse error"))
        }
        guard let method = message["method"] as? String else {
            // İstemciden gelen yanıt/geçersiz mesaj — sunucu istek göndermediği için yok sayılır.
            return .reply(status: 202, body: nil)
        }
        // Kimliksiz mesaj bildirimdir (`notifications/initialized` …): yanıtsız kabul.
        guard let id = RequestID(message["id"]) else {
            return .reply(status: 202, body: nil)
        }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let version = params["protocolVersion"] as? String ?? fallbackProtocolVersion
            return .reply(status: 200, body: result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": OrchestratorTools.serverName, "version": serverVersion],
            ]))
        case "ping":
            return .reply(status: 200, body: result(id: id, [:]))
        case "tools/list":
            return .reply(status: 200, body: result(id: id, ["tools": toolList()]))
        case "tools/call":
            guard let name = params["name"] as? String else {
                return .reply(status: 200, body: error(id: id, code: ErrorCode.invalidParams, message: "Missing tool name"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
            return .callTool(id: id, name: name, arguments: data)
        default:
            return .reply(status: 200, body: error(id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method)"))
        }
    }

    /// `tools/call` sonucu.
    static func toolResponse(id: RequestID, result toolResult: OrchestratorToolResult) -> Data {
        result(id: id, [
            "content": [["type": "text", "text": toolResult.text]],
            "isError": toolResult.isError,
        ])
    }

    private static func toolList() -> [[String: Any]] {
        OrchestratorTools.specs.map { spec in
            let schema = (try? JSONSerialization.jsonObject(with: Data(spec.inputSchema.utf8))) ?? ["type": "object"]
            return ["name": spec.name, "description": spec.description, "inputSchema": schema]
        }
    }

    private static func result(id: RequestID, _ value: [String: Any]) -> Data {
        encode(["jsonrpc": "2.0", "id": id.json, "result": value])
    }

    private static func error(id: RequestID?, code: Int, message: String) -> Data {
        encode(["jsonrpc": "2.0", "id": id?.json ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}
