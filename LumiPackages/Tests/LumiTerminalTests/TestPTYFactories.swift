import Foundation
@testable import LumiTerminal

/// Faz 4.1 test altyapısı: `TerminalSession`'a enjekte edilen PTY fabrikaları.
///
/// Ek A §A.2-12 gereği reattach kanıtı GERÇEK bir PTY ister — bu yüzden
/// `RecordingPTYSpawner` gerçek `SystemPTYSpawner`'ı çağırır, yalnız
/// executable/args'ı test komutuyla değiştirir ve dönen `PTYControlling`'i
/// byte/resize sayan bir sarmalayıcıya sarar. Ölçüm noktası artık üretim
/// tipinde test-only kanca değil, enjeksiyon sınırıdır.
struct RecordingPTYSpawner: PTYSpawning {
    let executable: String
    let args: [String]
    let recorder: PTYRecorder

    init(executable: String, args: [String] = [], recorder: PTYRecorder = PTYRecorder()) {
        self.executable = executable
        self.args = args
        self.recorder = recorder
    }

    func spawn(
        executable _: String,
        args _: [String],
        cwd: String,
        env: [String: String],
        cols: UInt16,
        rows: UInt16,
        queue: DispatchQueue
    ) throws -> any PTYControlling {
        let real = try SystemPTYSpawner().spawn(
            executable: executable,
            args: args,
            cwd: cwd,
            env: env,
            cols: cols,
            rows: rows,
            queue: queue
        )
        return RecordingPTY(wrapped: real, recorder: recorder)
    }
}

/// PTY'ye giden byte'ların ve ioctl'lerin thread-safe toplayıcısı
/// (io queue'dan yazılır, test thread'inden okunur).
final class PTYRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var writtenBytes = Data()
    private var resizes: [(cols: UInt16, rows: UInt16)] = []

    func noteWrite(_ data: Data) {
        lock.lock()
        writtenBytes.append(data)
        lock.unlock()
    }

    func noteResize(cols: UInt16, rows: UInt16) {
        lock.lock()
        resizes.append((cols, rows))
        lock.unlock()
    }

    var written: Data {
        lock.lock()
        defer { lock.unlock() }
        return writtenBytes
    }

    var totalBytes: Int { written.count }

    var allResizes: [(cols: UInt16, rows: UInt16)] {
        lock.lock()
        defer { lock.unlock() }
        return resizes
    }

    var resizeCount: Int { allResizes.count }
    var lastResize: (cols: UInt16, rows: UInt16)? { allResizes.last }

    var debugDescription: String {
        String(decoding: written, as: UTF8.self).debugDescription
    }
}

/// Gerçek PTY'yi saran, yazım/resize kaydeden dekoratör.
final class RecordingPTY: PTYControlling, @unchecked Sendable {
    private let wrapped: any PTYControlling
    private let recorder: PTYRecorder

    init(wrapped: any PTYControlling, recorder: PTYRecorder) {
        self.wrapped = wrapped
        self.recorder = recorder
    }

    var onExit: (@Sendable (Int32) -> Void)? {
        get { wrapped.onExit }
        set { wrapped.onExit = newValue }
    }

    var onWriteFailure: (@Sendable (Int32) -> Void)? {
        get { wrapped.onWriteFailure }
        set { wrapped.onWriteFailure = newValue }
    }

    func startReading(handler: @escaping @Sendable (Data) -> PTYProcess.ReadDirective) {
        wrapped.startReading(handler: handler)
    }

    func resumeReading() {
        wrapped.resumeReading()
    }

    func write(_ data: Data) {
        recorder.noteWrite(data)
        wrapped.write(data)
    }

    func resize(cols: UInt16, rows: UInt16) {
        recorder.noteResize(cols: cols, rows: rows)
        wrapped.resize(cols: cols, rows: rows)
    }

    func pokeRepaint() {
        wrapped.pokeRepaint()
    }

    func terminate() {
        wrapped.terminate()
    }
}

/// Süreç açmayan tamamen sahte PTY: `TerminalSession`'ı gerçek fork/exec
/// olmadan birim test etmeyi mümkün kılar (Faz 4.1 hedefi).
final class FakePTY: PTYControlling, @unchecked Sendable {
    let recorder = PTYRecorder()

    private let lock = NSLock()
    private var readHandler: (@Sendable (Data) -> PTYProcess.ReadDirective)?
    private var resumeCount = 0
    private var pokeCount = 0
    private var terminateCount = 0

    var onExit: (@Sendable (Int32) -> Void)?
    var onWriteFailure: (@Sendable (Int32) -> Void)?

    func startReading(handler: @escaping @Sendable (Data) -> PTYProcess.ReadDirective) {
        lock.lock()
        readHandler = handler
        lock.unlock()
    }

    /// Testin PTY'den veri geliyormuş gibi davranması için.
    @discardableResult
    func emitOutput(_ data: Data) -> PTYProcess.ReadDirective {
        lock.lock()
        let handler = readHandler
        lock.unlock()
        return handler?(data) ?? .proceed
    }

    func resumeReading() {
        lock.lock()
        resumeCount += 1
        lock.unlock()
    }

    func write(_ data: Data) {
        recorder.noteWrite(data)
    }

    func resize(cols: UInt16, rows: UInt16) {
        recorder.noteResize(cols: cols, rows: rows)
    }

    func pokeRepaint() {
        lock.lock()
        pokeCount += 1
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        terminateCount += 1
        lock.unlock()
    }

    var resumes: Int { counted { resumeCount } }
    var pokes: Int { counted { pokeCount } }
    var terminations: Int { counted { terminateCount } }

    private func counted(_ body: () -> Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

/// Sahte PTY üreten spawner; üretilen PTY testten erişilebilir.
struct FakePTYSpawner: PTYSpawning {
    let pty: FakePTY

    func spawn(
        executable _: String,
        args _: [String],
        cwd _: String,
        env _: [String: String],
        cols _: UInt16,
        rows _: UInt16,
        queue _: DispatchQueue
    ) throws -> any PTYControlling {
        pty
    }
}
