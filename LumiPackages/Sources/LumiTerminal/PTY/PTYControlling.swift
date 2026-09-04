import Foundation

/// `TerminalSession`'ın PTY'den ihtiyaç duyduğu yüzey (Faz 4.1 / DIP).
/// Somut `PTYProcess` bunun tek üretim implementasyonudur; testler gerçek PTY'yi
/// sarmalayan ya da tümüyle sahte bir implementasyon enjekte eder.
protocol PTYControlling: AnyObject, Sendable {
    var onExit: (@Sendable (Int32) -> Void)? { get set }
    var onWriteFailure: (@Sendable (Int32) -> Void)? { get set }

    func startReading(handler: @escaping @Sendable (Data) -> PTYProcess.ReadDirective)
    func resumeReading()
    func write(_ data: Data)
    func resize(cols: UInt16, rows: UInt16)
    func pokeRepaint()
    func terminate()
}

extension PTYProcess: PTYControlling {}

/// PTY üretimi (Faz 4.1): oturum, PTY'yi kendi `new`'lemez.
protocol PTYSpawning: Sendable {
    func spawn(
        executable: String,
        args: [String],
        cwd: String,
        env: [String: String],
        cols: UInt16,
        rows: UInt16,
        queue: DispatchQueue
    ) throws -> any PTYControlling
}

/// Üretim implementasyonu: gerçek `PTYProcess` (forkpty + dispatch source'lar).
struct SystemPTYSpawner: PTYSpawning {
    func spawn(
        executable: String,
        args: [String],
        cwd: String,
        env: [String: String],
        cols: UInt16,
        rows: UInt16,
        queue: DispatchQueue
    ) throws -> any PTYControlling {
        try PTYProcess(
            executable: executable,
            args: args,
            cwd: cwd,
            env: env,
            initialCols: cols,
            initialRows: rows,
            queue: queue
        )
    }
}
