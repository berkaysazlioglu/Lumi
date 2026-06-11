import Darwin
import Foundation
import LumiKit

/// forkpty tabanlı PTY wrapper'ı (design/01 §2).
///
/// SwiftTerm `LocalProcess` yerine kendi katmanımız: watermark backpressure için
/// fd okumasının suspend/resume kancası bizde olmalı (spec/00 §4.1-2). Tüm I/O
/// tek serial io queue üzerinde akar; `write`/`resize` o queue'dan çağrılır.
public final class PTYProcess: @unchecked Sendable {
    public enum ReadDirective: Equatable {
        case proceed
        case suspend
    }

    static let readChunkSize = 64 * 1024
    static let killEscalationDelay: TimeInterval = 3.0

    public let pid: pid_t

    private let masterFD: Int32
    private let queue: DispatchQueue
    private let lock = NSLock()

    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var readSuspended = false
    private var writeArmed = false
    private var didExit = false
    private var cleanedUp = false
    private var readBuffer = [UInt8](repeating: 0, count: PTYProcess.readChunkSize)
    private var pendingWrite = Data()
    private var readHandler: (@Sendable (Data) -> ReadDirective)?

    /// io queue üzerinde çağrılır; exit kodu (sinyalle ölümde 128+signo) taşır.
    /// @Sendable: aktör-izole bağlamda oluşturulan closure'ın izolasyon miras
    /// almasını engeller — io queue'dan çağrılır.
    public var onExit: (@Sendable (Int32) -> Void)?

    public init(
        executable: String,
        args: [String],
        cwd: String,
        env: [String: String],
        initialCols: UInt16,
        initialRows: UInt16,
        queue: DispatchQueue
    ) throws {
        self.queue = queue

        // argv/envp child'da kullanılacak ham C dizileri — fork'tan ÖNCE hazırlanır;
        // fork ile exec arasında yalnız async-signal-safe çağrılar yapılabilir.
        let argvStrings = [executable] + args
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: argvStrings.count + 1)
        for (index, value) in argvStrings.enumerated() {
            argv[index] = strdup(value)
        }
        argv[argvStrings.count] = nil

        let envStrings = env.map { "\($0.key)=\($0.value)" }
        let envp = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: envStrings.count + 1)
        for (index, value) in envStrings.enumerated() {
            envp[index] = strdup(value)
        }
        envp[envStrings.count] = nil

        let cwdC = strdup(cwd)

        defer {
            for index in 0...argvStrings.count { free(argv[index]) }
            argv.deallocate()
            for index in 0...envStrings.count { free(envp[index]) }
            envp.deallocate()
            free(cwdC)
        }

        var windowSize = winsize(ws_row: initialRows, ws_col: initialCols, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = -1

        // SIGHUP dispozisyonu fork'tan ÖNCE default'a çekilir: child henüz schedule
        // edilmeden killpg(SIGHUP) gelirse, miras alınmış bir ignore sinyali yutardı
        // (child-içi reset o anda daha çalışmamış olur). Ebeveynde hemen geri yüklenir.
        let previousHupDisposition = signal(SIGHUP, SIG_DFL)
        let forkedPid = forkpty(&master, nil, nil, &windowSize)

        if forkedPid != 0 {
            // SIG_ERR yalnız geçersiz sinyal numarasında döner; SIGHUP için imkânsız
            signal(SIGHUP, previousHupDisposition)
        }

        if forkedPid < 0 {
            throw LumiError.spawnFailed(reason: "forkpty failed: errno \(errno)")
        }

        if forkedPid == 0 {
            // Child — yalnız async-signal-safe çağrılar.
            // Ignore edilen dispozisyonlar exec'i AŞAR (ör. test runner'ı SIGHUP'ı
            // ignore'larsa shell de ignore'lar ve killpg(SIGHUP) işlemez) — resetle.
            signal(SIGHUP, SIG_DFL)
            signal(SIGINT, SIG_DFL)
            signal(SIGQUIT, SIG_DFL)
            signal(SIGTERM, SIG_DFL)
            signal(SIGPIPE, SIG_DFL)
            var emptySet = sigset_t()
            sigemptyset(&emptySet)
            sigprocmask(SIG_SETMASK, &emptySet, nil)

            if let cwdC { _ = chdir(cwdC) }
            _ = execve(argv[0], argv, envp)
            _exit(127)
        }

        self.pid = forkedPid
        self.masterFD = master

        let flags = fcntl(master, F_GETFL)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)

        PTYChildRegistry.shared.register(forkedPid)
        installExitMonitor()
    }

    deinit {
        // Normal yol kill/exit üzerinden temizler; bu, test/hata yolları için emniyettir.
        if !cleanedUp && masterFD >= 0 {
            close(masterFD)
        }
    }

    // MARK: - Okuma

    /// Handler her readable event'te ≤64KB ham byte alır; `.suspend` dönerse
    /// kaynak kendini durdurur — kernel PTY buffer'ı dolunca yazan süreç bloklanır,
    /// veri kaybı olmaz (spec/00 §4.1-2).
    public func startReading(handler: @escaping @Sendable (Data) -> ReadDirective) {
        readHandler = handler
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleReadable()
        }
        source.setCancelHandler { [weak self] in
            self?.closeMasterIfNeeded()
        }
        readSource = source
        source.activate()
    }

    public func resumeReading() {
        lock.lock()
        defer { lock.unlock() }
        guard readSuspended, !cleanedUp, let source = readSource else { return }
        readSuspended = false
        source.resume()
    }

    private func handleReadable() {
        let bytesRead = read(masterFD, &readBuffer, readBuffer.count)
        if bytesRead > 0 {
            let data = Data(bytes: readBuffer, count: bytesRead)
            if readHandler?(data) == .suspend {
                suspendReading()
            }
            return
        }
        if bytesRead == 0 {
            handleEOF()
            return
        }
        switch errno {
        case EAGAIN, EINTR:
            return
        default:
            // EIO: slave kapandı (child öldü) — EOF ile eşdeğer
            handleEOF()
        }
    }

    private func suspendReading() {
        lock.lock()
        defer { lock.unlock() }
        guard !readSuspended, !cleanedUp, let source = readSource else { return }
        readSuspended = true
        source.suspend()
    }

    private func handleEOF() {
        cleanupIO()
        reapAndNotify()
    }

    // MARK: - Yazma

    /// io queue üzerinde çağrılmalıdır. EAGAIN'de bekleyen buffer'a alınır ve
    /// write source ile drene edilir — kısmi yazım kaybı olmaz.
    public func write(_ data: Data) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !didExit, !cleanedUp else { return }
        pendingWrite.append(data)
        drainWrites()
    }

    private func drainWrites() {
        while !pendingWrite.isEmpty {
            let written = pendingWrite.withUnsafeBytes { pointer -> Int in
                guard let base = pointer.baseAddress else { return 0 }
                return Darwin.write(masterFD, base, pointer.count)
            }
            if written > 0 {
                pendingWrite.removeFirst(written)
                continue
            }
            if written < 0 && errno == EINTR { continue }
            if written < 0 && errno == EAGAIN {
                armWriteSource()
                return
            }
            // EPIPE vb. — child öldü; bekleyen yazım anlamsız
            pendingWrite.removeAll()
            return
        }
        disarmWriteSource()
    }

    private func armWriteSource() {
        if writeSource == nil {
            let source = DispatchSource.makeWriteSource(fileDescriptor: masterFD, queue: queue)
            source.setEventHandler { [weak self] in
                self?.drainWrites()
            }
            writeSource = source
            source.activate()
            writeArmed = true
            return
        }
        if !writeArmed {
            writeArmed = true
            writeSource?.resume()
        }
    }

    private func disarmWriteSource() {
        guard writeArmed, let source = writeSource else { return }
        writeArmed = false
        source.suspend()
    }

    // MARK: - Boyut / yaşam döngüsü

    public func resize(cols: UInt16, rows: UInt16) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !cleanedUp else { return }
        var windowSize = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &windowSize)
    }

    /// Process group'a SIGHUP; 3 sn içinde ölmezse SIGKILL (design/01 §2).
    /// forkpty çocuğu session leader olduğundan pgid == pid — login shell altındaki
    /// tüm claude ağacı hedeflenir.
    public func terminate() {
        queue.async { [weak self] in
            guard let self, !self.didExit else { return }
            self.signalProcessTree(SIGHUP)
            self.queue.asyncAfter(deadline: .now() + Self.killEscalationDelay) { [weak self] in
                guard let self, !self.didExit else { return }
                self.signalProcessTree(SIGKILL)
            }
        }
    }

    /// killpg, child'ın setsid'inden önce ESRCH ile başarısız olabilir (forkpty her
    /// iki process'e de döner; pgid henüz oluşmamış olabilir) — process'i doğrudan
    /// hedefleyen kill fallback'i o pencereyi kapatır.
    private func signalProcessTree(_ signalNumber: Int32) {
        if killpg(pid, signalNumber) != 0 {
            kill(pid, signalNumber)
        }
    }

    private func installExitMonitor() {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in
            self?.reapAndNotify()
        }
        source.activate()
        // Kayıt yarışı: process kaynaktan önce öldüyse event hiç gelmeyebilir
        if kill(pid, 0) != 0 && errno == ESRCH {
            queue.async { [weak self] in self?.reapAndNotify() }
        }
        // Kaynağın yaşaması için referans tut — exit'te cleanup ile bırakılır
        exitSource = source
    }

    private var exitSource: DispatchSourceProcess?

    private func reapAndNotify() {
        guard !didExit else { return }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == 0 {
            // Henüz reap edilemiyor — kısa aralıkla yeniden dene
            queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.reapAndNotify()
            }
            return
        }
        didExit = true
        PTYChildRegistry.shared.unregister(pid)
        cleanupIO()
        exitSource?.cancel()
        exitSource = nil
        onExit?(Self.exitCode(fromWaitStatus: status, waitResult: result))
    }

    private func cleanupIO() {
        lock.lock()
        let alreadyCleaned = cleanedUp
        cleanedUp = true
        let wasSuspended = readSuspended
        readSuspended = false
        let wasWriteDisarmed = !writeArmed
        writeArmed = true
        lock.unlock()
        guard !alreadyCleaned else { return }

        pendingWrite.removeAll()
        // Suspended source cancel edilemez — önce resume (Dispatch kuralı)
        if wasSuspended { readSource?.resume() }
        if let writeSource {
            if wasWriteDisarmed { writeSource.resume() }
            writeSource.cancel()
            self.writeSource = nil
        }
        if let readSource {
            readSource.cancel() // cancel handler fd'yi kapatır
            self.readSource = nil
        } else {
            closeMasterIfNeeded()
        }
    }

    private var masterClosed = false

    private func closeMasterIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !masterClosed else { return }
        masterClosed = true
        close(masterFD)
    }

    // MARK: - Wait status çözümleme (C makrolarının Swift karşılığı)

    static func exitCode(fromWaitStatus status: Int32, waitResult: pid_t) -> Int32 {
        guard waitResult > 0 else { return -1 }
        let lower = status & 0x7F
        if lower == 0 {
            return (status >> 8) & 0xFF // WIFEXITED → WEXITSTATUS
        }
        if lower != 0x7F {
            return 128 + lower // WIFSIGNALED → 128 + WTERMSIG
        }
        return -1
    }
}
