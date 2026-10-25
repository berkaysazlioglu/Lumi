import Foundation
import LumiKit

/// Bellek içi oturum sunucusu: liste, indirme, yükleme ve silme çağrılarını
/// kaydeder; `failure` ayarlıysa her çağrı onu fırlatır.
public actor FakeSessionSharing: SessionSharing {
    public var info: SessionServerInfo
    public var sessions: [SharedSession]
    public var archives: [String: Data] = [:]
    public var failure: (any Error)?
    public private(set) var listCount = 0
    public private(set) var uploads: [SharedSessionUpload] = []
    public private(set) var deleted: [String] = []

    public init(
        info: SessionServerInfo = SessionServerInfo(name: "Team", me: SharedSessionUploader(id: "u_me", name: "Me")),
        sessions: [SharedSession] = []
    ) {
        self.info = info
        self.sessions = sessions
    }

    public func setFailure(_ value: (any Error)?) { failure = value }
    public func setSessions(_ value: [SharedSession]) { sessions = value }
    public func setInfo(_ value: SessionServerInfo) { info = value }

    public func discover() async throws -> SessionServerInfo {
        if let failure { throw failure }
        return info
    }

    public func listSessions() async throws -> [SharedSession] {
        listCount += 1
        if let failure { throw failure }
        return sessions
    }

    public func download(sessionID: String) async throws -> Data {
        if let failure { throw failure }
        guard let data = archives[sessionID] ?? (sessions.contains { $0.id == sessionID } ? Data("{}".utf8) : nil) else {
            throw SessionShareFailure(kind: .notFound)
        }
        return data
    }

    public func upload(_ upload: SharedSessionUpload) async throws -> SharedSession {
        if let failure { throw failure }
        uploads.append(upload)
        let session = SharedSession(
            id: "s_\(uploads.count)", title: upload.title, project: upload.project, provider: upload.provider,
            uploader: info.me, uploadedAt: Date(), sizeBytes: upload.archive.count
        )
        sessions.insert(session, at: 0)
        return session
    }

    public func delete(sessionID: String) async throws {
        if let failure { throw failure }
        deleted.append(sessionID)
        sessions.removeAll { $0.id == sessionID }
    }
}

/// Her bağlantıda aynı fake sunucuyu döner; hangi adres/token'la kurulduğunu kaydeder.
public final class FakeSessionSharingFactory: SessionSharingMaking, @unchecked Sendable {
    public let server: FakeSessionSharing
    private let lock = NSLock()
    private var _made: [(baseURL: URL, token: String)] = []

    public init(server: FakeSessionSharing = FakeSessionSharing()) {
        self.server = server
    }

    public var made: [(baseURL: URL, token: String)] {
        lock.withLock { _made }
    }

    public func makeClient(baseURL: URL, token: String) -> any SessionSharing {
        lock.withLock { _made.append((baseURL, token)) }
        return server
    }
}

public actor FakeSessionServerCredentialStore: SessionServerCredentialStoring {
    public private(set) var tokens: [String: String] = [:]

    public init(tokens: [String: String] = [:]) {
        self.tokens = tokens
    }

    public func token(for serverID: String) async -> KeychainReadResult {
        tokens[serverID].map(KeychainReadResult.found) ?? .missing
    }

    public func setToken(_ token: String, for serverID: String) async throws {
        tokens[serverID] = token
    }

    public func deleteToken(for serverID: String) async throws {
        tokens.removeValue(forKey: serverID)
    }
}
