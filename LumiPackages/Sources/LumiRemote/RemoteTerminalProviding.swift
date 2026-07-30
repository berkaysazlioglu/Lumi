import Foundation
import LumiKit

/// Dashboard'a listelenen terminal özeti — HTTP/WS JSON gövdesi.
public struct RemoteTerminalSummary: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let repoPath: String
    public let repoName: String
    public let status: String
    public let task: String?
    public let title: String?

    public init(
        id: String,
        name: String,
        repoPath: String,
        repoName: String,
        status: String,
        task: String?,
        title: String?
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.repoName = repoName
        self.status = status
        self.task = task
        self.title = title
    }

    public init(meta: TerminalMeta) {
        self.init(
            id: meta.id.raw.uuidString,
            name: meta.name,
            repoPath: meta.repoPath,
            repoName: (meta.repoPath as NSString).lastPathComponent,
            status: meta.status.rawValue,
            task: meta.task,
            title: meta.oscTitle
        )
    }
}

/// Sunucunun terminal alt sistemine bakan yüzü (design/06). Server ve WS
/// oturumu yalnız bu soyutlamayı görür; MainActor detayı adapter'da kalır.
/// Böylece socket/route mantığı sahte provider'la test edilebilir.
public protocol RemoteTerminalProviding: Sendable {
    func listTerminals() async -> [RemoteTerminalSummary]
    func terminal(id: String) async -> RemoteTerminalSummary?
    /// Buffer'ın stilli anlık görüntüsü; terminal yoksa nil.
    func screenSnapshot(id: String) async -> TerminalScreenSnapshot?
    /// Ham girdi bayt'ları (tuş dizileri, escape kodları). Başarı durumu döner.
    func sendInput(id: String, rawText: String) async -> Bool
    /// Çok satırlı prompt — bracketed-paste ile sarılıp CR ile submit edilir.
    func sendPrompt(id: String, prompt: String) async -> Bool
    /// Çıktı aktivite sinyali (snapshot tetikleyici); terminal yoksa nil.
    func outputSignal(id: String) async -> AsyncStream<String>?
}

/// `TerminalServicing` üstüne remote köprüsü: string ID çözümü + MainActor
/// sıçramaları. İş kuralı içermez — saf adaptasyon (SRP).
public final class TerminalServiceRemoteAdapter: RemoteTerminalProviding {
    private let service: any TerminalServicing

    public init(service: any TerminalServicing) {
        self.service = service
    }

    public func listTerminals() async -> [RemoteTerminalSummary] {
        await MainActor.run { service.terminals.map(RemoteTerminalSummary.init(meta:)) }
    }

    public func terminal(id: String) async -> RemoteTerminalSummary? {
        guard let terminalID = Self.terminalID(from: id) else { return nil }
        return await MainActor.run {
            service.terminals
                .first { $0.id == terminalID }
                .map(RemoteTerminalSummary.init(meta:))
        }
    }

    public func screenSnapshot(id: String) async -> TerminalScreenSnapshot? {
        guard let terminalID = Self.terminalID(from: id) else { return nil }
        return await MainActor.run { service.screenSnapshot(id: terminalID) }
    }

    public func sendInput(id: String, rawText: String) async -> Bool {
        guard let terminalID = Self.terminalID(from: id) else { return false }
        return await MainActor.run {
            (try? service.write(id: terminalID, text: rawText)) != nil
        }
    }

    public func sendPrompt(id: String, prompt: String) async -> Bool {
        guard !prompt.isEmpty else { return false }
        return await sendInput(id: id, rawText: PromptInjection.encode(prompt))
    }

    public func outputSignal(id: String) async -> AsyncStream<String>? {
        guard let terminalID = Self.terminalID(from: id) else { return nil }
        return await MainActor.run { service.outputStream(id: terminalID) }
    }

    private static func terminalID(from raw: String) -> TerminalID? {
        UUID(uuidString: raw).map(TerminalID.init(raw:))
    }
}
