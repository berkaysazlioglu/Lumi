import Foundation
import LumiKit

/// Ekran anlık görüntüsünü mobil bağlantıya taşınabilir boyutta tutar.
enum SnapshotClipper {
    /// Son `maxLines` satırı döner; metin daha kısaysa aynen bırakır.
    static func tail(_ text: String, maxLines: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return text }
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}

/// Tek WS bağlantısının durum makinesi: `attach` ile terminale bağlanır,
/// çıktı sinyalini kirli-bayrağa çevirir ve sabit aralıkla (coalesced)
/// tam-ekran snapshot yayınlar; `input`/`prompt` mesajlarını PTY'ye iletir.
/// Ağ katmanından bağımsızdır — testler sahte provider + closure ile sürer.
public actor TerminalSocketSession {
    /// Snapshot yayın aralığı: çıktı seli tek gönderime coalesce edilir.
    public static let snapshotInterval: Duration = .milliseconds(500)
    /// Mobilde makul payload: scrollback kuyruğunun son N satırı (görünür
    /// ekran ayrıca stilli gönderilir, bu sınıra dahil değildir).
    public static let maxSnapshotLines = 400

    private let provider: any RemoteTerminalProviding
    private let send: @Sendable (String) -> Void
    private let close: @Sendable () -> Void

    private var attachedID: String?
    private var lastStatus: String?
    private var isDirty = false
    private var isFinished = false
    private var watchTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    public init(
        provider: any RemoteTerminalProviding,
        send: @escaping @Sendable (String) -> Void,
        close: @escaping @Sendable () -> Void
    ) {
        self.provider = provider
        self.send = send
        self.close = close
    }

    public func handle(_ raw: String) async {
        guard !isFinished else { return }
        guard let message = RemoteMessageCodec.decodeClient(raw) else {
            emit(.error(message: "Unrecognized message"))
            return
        }
        switch message {
        case .attach(let id):
            await attach(id)
        case .input(let data):
            guard let id = attachedID else {
                emit(.error(message: "Not attached"))
                return
            }
            if await !provider.sendInput(id: id, rawText: data) {
                emit(.error(message: "Terminal rejected input"))
            }
        case .prompt(let text):
            guard let id = attachedID else {
                emit(.error(message: "Not attached"))
                return
            }
            if await !provider.sendPrompt(id: id, prompt: text) {
                emit(.error(message: "Terminal rejected prompt"))
            }
        }
    }

    /// Bağlantı kapanışı: döngü task'ları iptal edilir, tekrar kullanılmaz.
    public func finish() {
        isFinished = true
        watchTask?.cancel()
        tickTask?.cancel()
        watchTask = nil
        tickTask = nil
    }

    private func attach(_ id: String) async {
        guard attachedID == nil else {
            emit(.error(message: "Already attached"))
            return
        }
        guard await provider.terminal(id: id) != nil,
              let signal = await provider.outputSignal(id: id) else {
            emit(.error(message: "Terminal not found"))
            close()
            return
        }
        attachedID = id
        await pushSnapshot()

        watchTask = Task { [weak self] in
            for await _ in signal {
                guard let self, !Task.isCancelled else { return }
                await self.markDirty()
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.snapshotInterval)
                guard let self else { return }
                await self.tick()
            }
        }
    }

    private func markDirty() {
        isDirty = true
    }

    /// Periyodik yayın kapısı: çıktı geldiyse VEYA status değiştiyse gönderir
    /// (status geçişleri — ör. working → waiting — çıktı üretmeden olabilir).
    /// Terminal listeden düştüyse `exited` yayınlar ve bağlantıyı kapatır.
    private func tick() async {
        guard !isFinished, let id = attachedID else { return }
        guard let terminal = await provider.terminal(id: id) else {
            emit(.exited)
            finish()
            close()
            return
        }
        guard isDirty || terminal.status != lastStatus else { return }
        isDirty = false
        await pushSnapshot(terminal)
    }

    private func pushSnapshot(_ known: RemoteTerminalSummary? = nil) async {
        guard let id = attachedID else { return }
        var resolved = known
        if resolved == nil {
            resolved = await provider.terminal(id: id)
        }
        guard let terminal = resolved,
              let snapshot = await provider.screenSnapshot(id: id) else {
            emit(.exited)
            finish()
            close()
            return
        }
        lastStatus = terminal.status
        let clipped = TerminalScreenSnapshot(
            history: SnapshotClipper.tail(snapshot.history, maxLines: Self.maxSnapshotLines),
            screen: snapshot.screen
        )
        emit(.snapshot(snapshot: clipped, terminal: terminal))
    }

    private func emit(_ message: RemoteServerMessage) {
        send(RemoteMessageCodec.encodeServer(message))
    }
}
