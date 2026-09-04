import Foundation

/// `codex app-server`'a stdio üzerinden JSON-RPC konuşup tek bir sonuç okuyan
/// probe (Orca paritesi — `codex-rpc-rate-limit-probe.ts`).
///
/// Protokol sırası (deneyle doğrulandı, codex-cli 0.153.2):
/// 1. `initialize` isteği → yanıt beklenir,
/// 2. `initialized` bildirimi + hedef istek aynı anda yazılır,
/// 3. hedef isteğin id'li yanıtı okunur.
///
/// **Kritik:** stdin yanıt gelene kadar AÇIK tutulmalıdır. Üç mesajı peş peşe
/// yazıp stdin'i kapatmak (ör. `ProcessRunner`'ın standardInput'u) sunucunun
/// ikinci isteği hiç yanıtlamamasına yol açıyor — EOF'u kapanma sinyali sayıyor.
/// Bu yüzden burada `ProcessRunner` kullanılmaz, kendi pipe yaşam döngüsü vardır.
///
/// Stdout satır-akışıdır: id'siz satırlar (`remoteControl/status/changed` gibi
/// bildirimler) atlanır.
enum CodexAppServerProbe {
    /// `codex`'i salt-okunur ve onaysız kipte açan argümanlar (Orca birebir):
    /// probe hiçbir şey çalıştırmaz, yalnız hesap durumunu okur.
    static let readOnlyArguments = [
        "-c", "approval_policy=never",
        "-s", "read-only",
        "-a", "never",
        "app-server",
    ]

    enum ProbeError: Error {
        /// Süreç başlatılamadı (binary yok/çalıştırılamıyor).
        case launchFailed
        /// Verilen sürede yanıt gelmedi.
        case timedOut
        /// Süreç yanıt vermeden kapandı; stderr özeti taşınır.
        case exitedEarly(String)
        /// Sunucu JSON-RPC hatası döndürdü.
        case rpc(String)
    }

    /// `initialize` + `method` konuşmasını yürütüp hedef yanıtın HAM satırını
    /// döner. `[String: Any]` yerine `Data`: sözlük Sendable değildir ve actor
    /// sınırını geçemez; parse çağıranın (saf `CodexUsageParser`) işidir.
    static func requestResponseLine(
        binary: String,
        method: String,
        timeout: TimeInterval
    ) async throws -> Data {
        let session = try ProbeSession(binary: binary)
        defer { session.shutdown() }

        let deadline = Date().addingTimeInterval(timeout)
        session.send(request: 1, method: "initialize", params: [
            "clientInfo": ["name": "lumi", "version": "1.0"],
        ])
        _ = try await session.awaitResponse(id: 1, deadline: deadline)

        session.send(notification: "initialized")
        session.send(request: 2, method: method, params: [:])
        return try await session.awaitResponse(id: 2, deadline: deadline)
    }
}

/// Tek probe süreci: pipe'lar, satır tamponu ve sonlandırma. `@unchecked
/// Sendable` — tüm paylaşılan durum `lock` altında (readabilityHandler arbitrer
/// thread'den yazar).
private final class ProbeSession: @unchecked Sendable {
    /// Yanıt bekleme döngüsünün yoklama aralığı — pipe okuması thread'den gelir,
    /// bunu bir continuation'a bağlamak yerine kısa aralıkla yoklamak yeterlidir.
    private static let pollInterval: Duration = .milliseconds(50)

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()

    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: Result<Data, CodexAppServerProbe.ProbeError>] = [:]
    private var stderrText = ""
    private var isShutDown = false

    init(binary: String) throws {
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = CodexAppServerProbe.readOnlyArguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ingest(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ingestStderr(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            shutdown()
            throw CodexAppServerProbe.ProbeError.launchFailed
        }
    }

    // MARK: - Yazma

    func send(request id: Int, method: String, params: [String: Any]) {
        write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
    }

    func send(notification method: String) {
        write(["jsonrpc": "2.0", "method": method, "params": [:]])
    }

    private func write(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        var line = data
        line.append(0x0A)
        // Süreç ölmüşse write SIGPIPE/exception üretir; sessizce yutulur —
        // bekleyen okuma zaten exitedEarly/timedOut ile sonuçlanır.
        try? stdinPipe.fileHandleForWriting.write(contentsOf: line)
    }

    // MARK: - Okuma

    func awaitResponse(id: Int, deadline: Date) async throws -> Data {
        while true {
            if let result = takeResponse(id: id) { return try result.get() }
            if Date() >= deadline { throw CodexAppServerProbe.ProbeError.timedOut }
            if !process.isRunning {
                // Kapanışta son chunk'lar hâlâ handler'a düşebilir; bir tur daha bak.
                try? await Task.sleep(for: Self.pollInterval)
                if let result = takeResponse(id: id) { return try result.get() }
                throw CodexAppServerProbe.ProbeError.exitedEarly(stderrExcerpt())
            }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func takeResponse(
        id: Int
    ) -> Result<Data, CodexAppServerProbe.ProbeError>? {
        lock.lock()
        defer { lock.unlock() }
        return responses.removeValue(forKey: id)
    }

    private func ingest(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        buffer.append(chunk)
        let lines = splitCompleteLines()
        lock.unlock()
        for line in lines { handle(line: line) }
    }

    /// `lock` altında çağrılır: tamponu tam satırlara böler, kalanı saklar.
    private func splitCompleteLines() -> [Data] {
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex ..< index])
            buffer = buffer[buffer.index(after: index)...]
        }
        return lines
    }

    private func handle(line: Data) {
        guard !line.isEmpty,
              let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = message["id"] as? Int else {
            // id'siz satırlar sunucu bildirimleridir (protokolün parçası değil).
            return
        }
        let outcome: Result<Data, CodexAppServerProbe.ProbeError>
        if let error = message["error"] as? [String: Any] {
            let detail = (error["message"] as? String) ?? "unknown RPC error"
            outcome = .failure(.rpc(detail))
        } else {
            outcome = .success(line)
        }
        lock.lock()
        responses[id] = outcome
        lock.unlock()
    }

    private func ingestStderr(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        stderrText += String(decoding: chunk, as: UTF8.self)
    }

    private func stderrExcerpt() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stderrText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .suffix(2)
            .joined(separator: " ")
    }

    // MARK: - Sonlandırma

    func shutdown() {
        lock.lock()
        let alreadyDone = isShutDown
        isShutDown = true
        lock.unlock()
        guard !alreadyDone else { return }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
