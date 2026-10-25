import CryptoKit
import Foundation
import LumiKit

/// Task görsellerinin disk önbelleği (Tasks planı: "Görseller").
///
/// - `file://` adresleri olduğu gibi döner (demo kaynak, yerel sunucu).
/// - `https` görseli bir kez indirilir, kimliğinin (`TaskImageIdentity` —
///   pre-signed imza parametreleri atılmış adres) SHA-256'sıyla adlandırılıp
///   önbellek dizinine yazılır; imzası tazelenen aynı görsel ağa çıkmaz.
/// - Aynı görsel için eşzamanlı istekler tek indirmeye bağlanır.
/// - Dizin `maxBytes`'ı aşınca en eski dosyalar silinir.
public actor TaskImageCache: TaskImageLoading {
    private let directory: URL
    /// Ajanlara verilen görsellerin kökü: `<root>/<kaynak>/<task>/1-ad.png`.
    private let attachmentsRoot: URL
    private let session: URLSession
    private let maxBytes: Int
    private var inFlight: [String: Task<URL, any Error>] = [:]

    public init(
        directory: URL, attachmentsRoot: URL, session: URLSession = .shared, maxBytes: Int = 200 * 1024 * 1024
    ) {
        self.directory = directory
        self.attachmentsRoot = attachmentsRoot
        self.session = session
        self.maxBytes = maxBytes
    }

    public func localFile(for url: URL, authorization: String?) async throws -> URL {
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { throw TaskProviderError.notFound }
            return url
        }
        let target = cachedPath(for: url)
        if FileManager.default.fileExists(atPath: target.path) {
            // Erişim zamanı budamada "yeni kullanıldı" sayılsın.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            return target
        }
        let key = TaskImageIdentity.key(for: url)
        if let running = inFlight[key] { return try await running.value }
        let download = Task { [session, directory] in
            try await Self.download(url, to: target, directory: directory, session: session, authorization: authorization)
        }
        inFlight[key] = download
        defer { inFlight[key] = nil }
        let file = try await download.value
        prune()
        return file
    }

    // MARK: - Ajan ekleri

    public func attachments(
        for task: TaskKey, images: [TaskImage], authorization: @escaping @Sendable (URL) -> String?
    ) async -> (directory: URL, files: [URL]) {
        let folder = attachmentFolder(for: task)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        for (index, image) in images.enumerated() {
            guard let local = try? await localFile(for: image.url, authorization: authorization(image.url)) else { continue }
            var name = Self.safeComponent(image.displayName)
            if (name as NSString).pathExtension.isEmpty, !local.pathExtension.isEmpty {
                name += "." + local.pathExtension
            }
            let target = folder.appendingPathComponent("\(index + 1)-\(name)")
            do {
                try FileManager.default.copyItem(at: local, to: target)
                files.append(target)
            } catch {
                continue
            }
        }
        return (folder, files)
    }

    public func removeAttachments(for tasks: [TaskKey]) {
        for task in tasks { try? FileManager.default.removeItem(at: attachmentFolder(for: task)) }
    }

    public func removeAttachments(source: TaskSourceID) {
        try? FileManager.default.removeItem(at: attachmentsRoot.appendingPathComponent(Self.safeComponent(source.rawValue)))
    }

    /// Önbellekten düşürür (yalnız indirilmiş `https` kopyaları; `file://`
    /// adresler kullanıcınındır, dokunulmaz).
    public func evict(_ urls: [URL]) {
        for url in urls where !url.isFileURL {
            try? FileManager.default.removeItem(at: cachedPath(for: url))
        }
    }

    private func attachmentFolder(for task: TaskKey) -> URL {
        attachmentsRoot
            .appendingPathComponent(Self.safeComponent(task.source.rawValue))
            .appendingPathComponent(Self.safeComponent(task.id))
    }

    /// Dosya adı olarak güvenli: yol ayırıcıları ve kontrol karakterleri `-`.
    static func safeComponent(_ raw: String) -> String {
        let cleaned = raw.map { character -> Character in
            character == "/" || character == ":" || character == "\\" || character.isNewline || character.asciiValue.map { $0 < 32 } == true
                ? "-" : character
        }
        let text = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return text.isEmpty ? "item" : String(text.prefix(80))
    }

    private func cachedPath(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(TaskImageIdentity.key(for: url).utf8)).map { String(format: "%02x", $0) }.joined()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
        return directory.appendingPathComponent("\(digest).\(ext)")
    }

    private static func download(
        _ url: URL, to target: URL, directory: URL, session: URLSession, authorization: String?
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        let (temporary, response) = try await session.download(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: temporary)
            throw TaskRequestFailure(
                kind: status == 401 ? .unauthorized : (status == 404 ? .notFound : .invalidResponse("HTTP \(status)")),
                operation: .loadImage, request: "GET \(url.absoluteString)", httpStatus: status
            )
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
    }

    /// En eski (son erişimi en eski) dosyalardan başlayarak sınırın altına iner.
    private func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return }
        let entries = files.compactMap { file -> (URL, Int, Date)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > maxBytes else { return }
        for (file, size, _) in entries.sorted(by: { $0.2 < $1.2 }) where total > maxBytes {
            try? FileManager.default.removeItem(at: file)
            total -= size
        }
    }
}
