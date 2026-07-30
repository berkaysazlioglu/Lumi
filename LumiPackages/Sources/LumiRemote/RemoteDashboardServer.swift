import FlyingFox
import Foundation
import LumiKit

/// Yerel ağ dashboard sunucusu (design/06): statik HTML + `/api/terminals`
/// listesi + `/ws` terminal soketi. Yaşam döngüsü kullanıcı kontrolündedir
/// (topbar popover'ı) — uygulama açılışında otomatik başlamaz.
///
/// Güvenlik modeli v1: kimlik doğrulama YOK; sunucu yalnız kullanıcı
/// başlattığında, yerel ağa açık çalışır. Güvenilmeyen ağlarda açık bırakılmamalı.
@MainActor
public final class RemoteDashboardServer: RemoteDashboardServing {
    public static let defaultPort: UInt16 = 8484
    /// Tercih edilen port doluysa (ör. ikinci Lumi instance'ı ya da eski bir
    /// sürümün PTY çocuklarında rehin kalmış soket) sırayla denenecek aralık.
    public static let portSearchRange: UInt16 = 10

    private let provider: any RemoteTerminalProviding
    private let preferredPort: UInt16
    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?

    public private(set) var status: RemoteDashboardStatus = .stopped

    public init(provider: any RemoteTerminalProviding, port: UInt16 = RemoteDashboardServer.defaultPort) {
        self.provider = provider
        self.preferredPort = port
    }

    public func start() async throws {
        guard !status.isRunning else { return }

        for candidate in preferredPort..<(preferredPort &+ Self.portSearchRange) {
            // Hızlı ön-eleme: dolu porta FlyingFox kurup timeout beklemek yerine
            // anlık bind probe'u — fallback taraması saniyeler değil milisaniyeler sürer.
            guard PortProbe.isAvailable(candidate) else { continue }

            let server = HTTPServer(port: candidate)
            await Self.configureRoutes(on: server, provider: provider)
            let runTask = Task { try await server.run() }
            do {
                try await server.waitUntilListening(timeout: 5)
            } catch {
                runTask.cancel()
                continue // probe ile start arası yarış — sıradakini dene
            }

            self.server = server
            self.serverTask = Task { _ = try? await runTask.value }
            let host = LocalNetworkAddress.primaryIPv4() ?? "127.0.0.1"
            status = RemoteDashboardStatus(isRunning: true, url: "http://\(host):\(candidate)")
            return
        }

        throw LumiError.remoteDashboardFailed(
            detail: "Port \(preferredPort)-\(preferredPort &+ Self.portSearchRange - 1) aralığında boş port yok"
        )
    }

    public func stop() async {
        guard let server else { return }
        await server.stop(timeout: 1)
        serverTask?.cancel()
        serverTask = nil
        self.server = nil
        status = .stopped
    }

    private nonisolated static func configureRoutes(
        on server: HTTPServer,
        provider: any RemoteTerminalProviding
    ) async {
        let html = DashboardPage.html()
        await server.appendRoute(HTTPRoute("GET /")) { _ in
            // no-store: sunucu ölüyken cache'ten gelen bayat sayfa "çalışıyor
            // ama boş" yanılsaması yaratmasın.
            HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "text/html; charset=utf-8", .cacheControl: "no-store"],
                body: html
            )
        }
        await server.appendRoute(HTTPRoute("GET /api/terminals")) { _ in
            let terminals = await provider.listTerminals()
            let body = (try? JSONEncoder().encode(TerminalListResponse(terminals: terminals))) ?? Data()
            return HTTPResponse(
                statusCode: .ok,
                headers: [.contentType: "application/json; charset=utf-8", .cacheControl: "no-store"],
                body: body
            )
        }
        await server.appendRoute(
            HTTPRoute("GET /ws"),
            to: .webSocket(TerminalSocketHandler(provider: provider))
        )
    }
}

/// `/api/terminals` cevap zarfı.
struct TerminalListResponse: Codable, Equatable {
    let terminals: [RemoteTerminalSummary]
}

/// FlyingFox WS köprüsü: her bağlantı için bir `TerminalSocketSession` kurar;
/// gelen text frame'leri oturuma iletir, oturumun ürettiklerini soket'e yazar.
struct TerminalSocketHandler: WSMessageHandler {
    let provider: any RemoteTerminalProviding

    func makeMessages(for client: AsyncStream<WSMessage>) async throws -> AsyncStream<WSMessage> {
        let (stream, continuation) = AsyncStream<WSMessage>.makeStream()
        let session = TerminalSocketSession(
            provider: provider,
            send: { continuation.yield(.text($0)) },
            close: { continuation.finish() }
        )
        Task {
            for await message in client {
                guard case .text(let raw) = message else { continue }
                await session.handle(raw)
            }
            await session.finish()
            continuation.finish()
        }
        return stream
    }
}

/// Statik dashboard sayfası — bundle kaynağından bir kez okunur.
enum DashboardPage {
    static func html() -> Data {
        guard let url = Bundle.module.url(forResource: "dashboard", withExtension: "html"),
              let data = try? Data(contentsOf: url) else {
            return Data("<h1>dashboard.html resource missing</h1>".utf8)
        }
        return data
    }
}
