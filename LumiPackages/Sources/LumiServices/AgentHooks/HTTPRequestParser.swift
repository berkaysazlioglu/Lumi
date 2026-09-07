import Foundation

/// Hook sunucusunun anladığı asgari HTTP/1.1 isteği (karar 45). Yalnız
/// `curl --data-binary` biçimindeki tek POST'u çözer: istek satırı, başlıklar,
/// `Content-Length` gövdesi. Chunked transfer, pipelining ya da keep-alive
/// desteklenmez — sunucu her yanıttan sonra bağlantıyı kapatır.
struct HTTPRequest: Equatable, Sendable {
    let method: String
    let path: String
    /// Küçük harfe indirgenmiş başlık adları.
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

enum HTTPRequestParser {
    enum Outcome: Equatable, Sendable {
        /// Başlıklar ya da gövde henüz tamamlanmadı; daha fazla byte bekle.
        case incomplete
        case complete(HTTPRequest)
        /// Bozuk istek satırı/başlık ya da bütçe aşımı — 400 ile kapat.
        case malformed
    }

    /// Başlık bölgesi için üst sınır (bütçe: kötü niyetli/bozuk istemci).
    static let maxHeaderBytes = 16 * 1024
    /// Hook gövdeleri birkaç KB'dir; 1 MiB üstü kesinlikle bizim değil.
    static let maxBodyBytes = 1024 * 1024

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    static func parse(_ buffer: Data) -> Outcome {
        guard let terminatorRange = buffer.range(of: headerTerminator) else {
            return buffer.count > maxHeaderBytes ? .malformed : .incomplete
        }
        let headerData = buffer[buffer.startIndex ..< terminatorRange.lowerBound]
        guard headerData.count <= maxHeaderBytes,
              let headerText = String(data: headerData, encoding: .utf8) else { return .malformed }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .malformed }
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .malformed }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .malformed }
            headers[name] = value
        }

        let contentLength: Int
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0 else { return .malformed }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= maxBodyBytes else { return .malformed }

        let bodyStart = terminatorRange.upperBound
        let available = buffer.endIndex - bodyStart
        guard available >= contentLength else { return .incomplete }
        let body = Data(buffer[bodyStart ..< bodyStart + contentLength])
        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: body
        ))
    }

    /// Tek satırlık yanıt üretici: gövde daima `{}` (Claude izin hook'ları boş
    /// stdout'ta fail-closed olduğu için script de bunu basar; sunucu cevabı
    /// script tarafından /dev/null'a atılır ama simetrik durur).
    static func response(status: Int, reason: String) -> Data {
        let body = "{}"
        let head = "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data((head + body).utf8)
    }
}
